import Accelerate
import Foundation

/// A single spectrum snapshot. Band levels are ordered from low to high frequency.
public struct SpectrumFrame: Equatable, Sendable {
    public let bands: [Float]
    /// Unwindowed signal RMS in dBFS, with a -100 dB floor.
    public let rmsDB: Float
    /// Dominant frequency in the displayed range, or zero when below the noise floor.
    public let peakFrequency: Double
    public let sampleRate: Double

    public init(bands: [Float], rmsDB: Float, peakFrequency: Double, sampleRate: Double) {
        self.bands = bands
        self.rmsDB = rmsDB
        self.peakFrequency = peakFrequency
        self.sampleRate = sampleRate
    }

    public static func silence(bandCount: Int = 64) -> SpectrumFrame {
        SpectrumFrame(
            bands: [Float](repeating: 0, count: max(0, bandCount)),
            rmsDB: -100,
            peakFrequency: 0,
            sampleRate: 0
        )
    }
}

/// A streaming, Hann-windowed FFT analyzer with logarithmic frequency bands.
///
/// Supply normalized, channel-aligned PCM on one serial queue. This class owns mutable FFT
/// storage and is intentionally not thread-safe. It processes every completed
/// window with 50% overlap, returning the latest snapshot when a call contains
/// several windows. It allocates, so call it outside the audio render callback.
public final class SpectrumAnalyzer {
    public let bandCount: Int
    public let fftSize: Int

    private let fftSetup: FFTSetup
    private let log2FFTSize: vDSP_Length
    private let hopSize: Int
    private let window: [Float]
    private let amplitudeScale: Float
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]
    private var magnitudePowers: [Float]
    private var pendingChannels: [[Float]] = []
    private var smoothedBands: [Float]
    private var currentSampleRate: Double?
    private var bandRanges: [BandRange] = []

    private static let minimumFrequency: Double = 40
    private static let maximumFrequency: Double = 20_000
    private static let displayFloorDB: Float = -80
    private static let attackSeconds = 0.035
    private static let decaySeconds = 0.22

    private struct BandRange {
        let firstBin: Int
        let lastBin: Int
        let centerBin: Double
    }

    /// `fftSize` must be a power of two of at least 32; `bandCount` must be positive.
    public init(bandCount: Int = 64, fftSize: Int = 4096) {
        precondition(bandCount > 0, "bandCount must be positive")
        precondition(fftSize >= 32 && fftSize.nonzeroBitCount == 1,
                     "fftSize must be a power of two of at least 32")

        self.bandCount = bandCount
        self.fftSize = fftSize
        hopSize = fftSize / 2
        log2FFTSize = vDSP_Length(fftSize.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2FFTSize, FFTRadix(kFFTRadix2)) else {
            preconditionFailure("Unable to allocate FFT setup")
        }
        fftSetup = setup

        // A periodic Hann window has an exact coherent gain of 0.5. Compute
        // the actual sum so the amplitude calibration also survives rounding.
        let hann = (0..<fftSize).map { index in
            Float(0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(fftSize)))
        }
        window = hann
        amplitudeScale = 2 / hann.reduce(0, +)
        real = [Float](repeating: 0, count: fftSize)
        imaginary = [Float](repeating: 0, count: fftSize)
        magnitudes = [Float](repeating: 0, count: fftSize / 2 + 1)
        magnitudePowers = [Float](repeating: 0, count: fftSize / 2 + 1)
        smoothedBands = [Float](repeating: 0, count: bandCount)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Adds mono samples and returns the newest completed FFT window.
    ///
    /// Nonfinite samples become zero and finite samples are clipped to the
    /// normalized PCM range. Invalid rates clear the stream and return nil.
    /// Changing the sample rate discards partial windows and smoothing history.
    public func consume(samples: [Float], sampleRate: Double) -> SpectrumFrame? {
        consume(channels: [samples], sampleRate: sampleRate)
    }

    /// Adds synchronized channel-major samples and returns the newest FFT window.
    ///
    /// Each channel must contain the same number of samples. Spectrum power is
    /// averaged across channels before converting to amplitude, so opposing
    /// stereo phases cannot cancel. RMS is measured over all channel samples.
    /// A channel-count change clears the stream; absent or unequal channels
    /// clear the stream and are dropped. Empty, aligned buffers add no samples.
    public func consume(channels: [[Float]], sampleRate: Double) -> SpectrumFrame? {
        guard sampleRate.isFinite, sampleRate > 0,
              sampleRate / Double(fftSize) > 0,
              let frameCount = channels.first?.count,
              channels.allSatisfy({ $0.count == frameCount }) else {
            reset()
            return nil
        }
        if currentSampleRate != sampleRate || pendingChannels.count != channels.count {
            reset()
            currentSampleRate = sampleRate
            configureBands(sampleRate: sampleRate)
            pendingChannels = channels.map { _ in
                var samples: [Float] = []
                samples.reserveCapacity(fftSize * 2)
                return samples
            }
        }
        guard frameCount > 0 else { return nil }

        for channel in channels.indices {
            pendingChannels[channel].append(contentsOf: channels[channel].map { sample in
                sample.isFinite ? min(1, max(-1, sample)) : 0
            })
        }

        var offset = 0
        var latestFrame: SpectrumFrame?
        while pendingChannels[0].count - offset >= fftSize {
            latestFrame = analyze(offset: offset, sampleRate: sampleRate)
            offset += hopSize
        }
        if offset > 0 {
            // Keep the overlap and any trailing partial window for the next call.
            for channel in pendingChannels.indices {
                pendingChannels[channel].removeFirst(offset)
            }
        }
        return latestFrame
    }

    public func reset() {
        pendingChannels.removeAll(keepingCapacity: true)
        smoothedBands = [Float](repeating: 0, count: bandCount)
        currentSampleRate = nil
        bandRanges.removeAll(keepingCapacity: true)
    }

    private func configureBands(sampleRate: Double) {
        let high = min(Self.maximumFrequency, sampleRate / 2)
        // Normal audio rates use 40 Hz. Keep even unusually low positive
        // rates well-defined instead of generating reversed logarithmic bands.
        let low = min(Self.minimumFrequency, high / 2)
        let ratio = high / low
        let binWidth = sampleRate / Double(fftSize)
        let lastBin = fftSize / 2
        bandRanges = (0..<bandCount).map { index in
            let lower = low * pow(ratio, Double(index) / Double(bandCount))
            let upper = low * pow(ratio, Double(index + 1) / Double(bandCount))
            let center = lower * sqrt(upper / lower) / binWidth
            return BandRange(
                firstBin: max(1, min(lastBin, Int(ceil(lower / binWidth)))),
                lastBin: max(0, min(lastBin, Int(floor(upper / binWidth)))),
                centerBin: max(0, min(Double(lastBin), center))
            )
        }
    }

    private func analyze(offset: Int, sampleRate: Double) -> SpectrumFrame {
        var sumSquares: Double = 0
        for index in magnitudePowers.indices {
            magnitudePowers[index] = 0
        }
        for channel in pendingChannels {
            var sum: Double = 0
            for index in 0..<fftSize {
                let sample = Double(channel[offset + index])
                sum += sample
                sumSquares += sample * sample
            }
            let mean = Float(sum / Double(fftSize))
            for index in 0..<fftSize {
                real[index] = (channel[offset + index] - mean) * window[index]
                imaginary[index] = 0
            }

            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                    var split = DSPSplitComplex(
                        realp: realBuffer.baseAddress!,
                        imagp: imaginaryBuffer.baseAddress!
                    )
                    vDSP_fft_zip(fftSetup, &split, 1, log2FFTSize, FFTDirection(FFT_FORWARD))
                }
            }
            for index in 1...fftSize / 2 {
                var amplitude = hypotf(real[index], imaginary[index]) * amplitudeScale
                // Nyquist has no negative-frequency partner in a one-sided FFT.
                if index == fftSize / 2 { amplitude *= 0.5 }
                magnitudePowers[index] += amplitude * amplitude
            }
        }
        let channelScale = 1 / Float(pendingChannels.count)
        for index in magnitudes.indices {
            magnitudes[index] = sqrtf(magnitudePowers[index] * channelScale)
        }

        let hopDuration = Double(hopSize) / sampleRate
        let attack = Float(1 - exp(-hopDuration / Self.attackSeconds))
        let decay = Float(1 - exp(-hopDuration / Self.decaySeconds))
        for index in 0..<bandCount {
            let range = bandRanges[index]
            var amplitude: Float = 0
            if range.firstBin <= range.lastBin {
                for bin in range.firstBin...range.lastBin {
                    amplitude = max(amplitude, magnitudes[bin])
                }
            } else {
                // At low frequencies a log band can be narrower than one FFT
                // bin. Interpolation avoids dead bars between bin centers.
                let lowerBin = Int(floor(range.centerBin))
                let upperBin = min(fftSize / 2, lowerBin + 1)
                let fraction = Float(range.centerBin - Double(lowerBin))
                amplitude = magnitudes[lowerBin] * (1 - fraction)
                    + magnitudes[upperBin] * fraction
            }
            let db = 20 * log10f(max(amplitude, 0.000_000_1))
            let level = min(1, max(0, (db - Self.displayFloorDB) / -Self.displayFloorDB))
            let coefficient = level > smoothedBands[index] ? attack : decay
            smoothedBands[index] += coefficient * (level - smoothedBands[index])
            if smoothedBands[index] < 0.000_1 {
                smoothedBands[index] = 0
            }
        }

        let rms = sqrt(sumSquares / (Double(fftSize) * Double(pendingChannels.count)))
        let rmsDB = Float(max(-100, min(0, 20 * log10(max(rms, 0.000_01)))))
        return SpectrumFrame(
            bands: smoothedBands,
            rmsDB: rmsDB,
            peakFrequency: dominantFrequency(sampleRate: sampleRate),
            sampleRate: sampleRate
        )
    }

    private func dominantFrequency(sampleRate: Double) -> Double {
        let binWidth = sampleRate / Double(fftSize)
        let high = min(Self.maximumFrequency, sampleRate / 2)
        let low = min(Self.minimumFrequency, high / 2)
        let firstBin = max(1, min(fftSize / 2, Int(ceil(low / binWidth))))
        let lastBin = max(0, min(fftSize / 2, Int(floor(high / binWidth))))
        guard firstBin <= lastBin else { return 0 }
        var peakBin = firstBin
        for bin in firstBin...lastBin where magnitudes[bin] > magnitudes[peakBin] {
            peakBin = bin
        }
        // Match the -80 dBFS display floor so silent input has no reported pitch.
        guard magnitudes[peakBin] >= 0.000_1 else { return 0 }

        var fractionalBin: Double = 0
        if peakBin > 0 && peakBin < fftSize / 2 {
            let left = log(Double(max(magnitudes[peakBin - 1], 1e-20)))
            let center = log(Double(max(magnitudes[peakBin], 1e-20)))
            let right = log(Double(max(magnitudes[peakBin + 1], 1e-20)))
            let curvature = left - 2 * center + right
            if abs(curvature) > 1e-12 {
                fractionalBin = max(-0.5, min(0.5, 0.5 * (left - right) / curvature))
            }
        }
        return min(high, max(low, (Double(peakBin) + fractionalBin) * binWidth))
    }
}
