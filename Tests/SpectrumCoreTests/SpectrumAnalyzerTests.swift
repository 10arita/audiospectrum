import XCTest
@testable import SpectrumCore

final class SpectrumAnalyzerTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let fftSize = 4096

    func testSilenceIsFiniteAndEmpty() throws {
        let analyzer = SpectrumAnalyzer()
        let frame = try XCTUnwrap(analyzer.consume(
            samples: [Float](repeating: 0, count: fftSize), sampleRate: sampleRate
        ))
        XCTAssertEqual(frame.bands.count, 64)
        XCTAssertTrue(frame.bands.allSatisfy { $0 == 0 })
        XCTAssertEqual(frame.rmsDB, -100)
        XCTAssertEqual(frame.peakFrequency, 0)
        XCTAssertEqual(frame.sampleRate, sampleRate)
    }

    func testSinePeakAndLogarithmicBandLocalization() throws {
        let analyzer = SpectrumAnalyzer()
        let frequency = 1_000.0
        let frame = try XCTUnwrap(analyzer.consume(
            samples: sine(frequency: frequency, amplitude: 0.5, count: fftSize * 8),
            sampleRate: sampleRate
        ))
        XCTAssertEqual(frame.peakFrequency, frequency, accuracy: 2)
        XCTAssertEqual(frame.rmsDB, -9.03, accuracy: 0.05)
        let strongestBand = try XCTUnwrap(frame.bands.indices.max { frame.bands[$0] < frame.bands[$1] })
        let expectedBand = Int(log(frequency / 40) / log(20_000.0 / 40) * 64)
        XCTAssertLessThanOrEqual(abs(strongestBand - expectedBand), 1)
        XCTAssertGreaterThan(frame.bands[strongestBand], 0.85)
        XCTAssertTrue(frame.bands.allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    func testAmplitudeRetainsDecibelDifference() throws {
        let loud = SpectrumAnalyzer()
        let quiet = SpectrumAnalyzer()
        // An exact FFT-bin tone isolates calibration from spectral leakage.
        let frequency = sampleRate * 128 / Double(fftSize)
        let loudFrame = try XCTUnwrap(loud.consume(
            samples: sine(frequency: frequency, amplitude: 0.5, count: fftSize * 10),
            sampleRate: sampleRate
        ))
        let quietFrame = try XCTUnwrap(quiet.consume(
            samples: sine(frequency: frequency, amplitude: 0.05, count: fftSize * 10),
            sampleRate: sampleRate
        ))
        XCTAssertEqual(loudFrame.rmsDB - quietFrame.rmsDB, 20, accuracy: 0.01)
        XCTAssertEqual((loudFrame.bands.max() ?? 0) - (quietFrame.bands.max() ?? 0),
                       20.0 / 80.0, accuracy: 0.005)
        XCTAssertEqual(loudFrame.bands.max() ?? 0, (80 - 6.0206) / 80, accuracy: 0.005)
    }

    func testArbitraryChunkBoundariesMatchContinuousStream() throws {
        let samples = sine(frequency: 732, amplitude: 0.3, count: fftSize * 5 + 777)
        let continuous = SpectrumAnalyzer()
        let expected = try XCTUnwrap(continuous.consume(samples: samples, sampleRate: sampleRate))
        let chunked = SpectrumAnalyzer()
        var actual: SpectrumFrame?
        var offset = 0
        let chunkSizes = [1, 137, 512, 31, 2_057, 64, 4_111]
        var chunk = 0
        while offset < samples.count {
            let end = min(samples.count, offset + chunkSizes[chunk % chunkSizes.count])
            if let frame = chunked.consume(samples: Array(samples[offset..<end]), sampleRate: sampleRate) {
                actual = frame
            }
            offset = end
            chunk += 1
        }
        XCTAssertEqual(try XCTUnwrap(actual), expected)
    }

    func testWaitsForCompleteWindowAndRetainsOverlap() {
        let analyzer = SpectrumAnalyzer()
        XCTAssertNil(analyzer.consume(samples: [Float](repeating: 0, count: fftSize - 1),
                                      sampleRate: sampleRate))
        XCTAssertNotNil(analyzer.consume(samples: [0], sampleRate: sampleRate))
        XCTAssertNil(analyzer.consume(samples: [Float](repeating: 0, count: fftSize / 2 - 1),
                                      sampleRate: sampleRate))
        XCTAssertNotNil(analyzer.consume(samples: [0], sampleRate: sampleRate))
    }

    func testSampleRateChangeDiscardsPreviousSamplesAndHistory() throws {
        let analyzer = SpectrumAnalyzer()
        _ = analyzer.consume(samples: sine(frequency: 1_000, amplitude: 1, count: fftSize),
                             sampleRate: sampleRate)
        XCTAssertNil(analyzer.consume(samples: [Float](repeating: 0, count: fftSize / 2),
                                      sampleRate: 44_100))
        let frame = try XCTUnwrap(analyzer.consume(samples: [Float](repeating: 0, count: fftSize / 2),
                                                  sampleRate: 44_100))
        XCTAssertEqual(frame.sampleRate, 44_100)
        XCTAssertTrue(frame.bands.allSatisfy { $0 == 0 })
        XCTAssertEqual(frame.rmsDB, -100)
    }

    func testInvalidRatesClearPartialInput() throws {
        let analyzer = SpectrumAnalyzer()
        for invalidRate in [0, -1, Double.nan, Double.infinity, Double.leastNonzeroMagnitude] {
            _ = analyzer.consume(samples: [Float](repeating: 1, count: fftSize / 2),
                                 sampleRate: sampleRate)
            XCTAssertNil(analyzer.consume(samples: [0], sampleRate: invalidRate))
            XCTAssertNil(analyzer.consume(samples: [Float](repeating: 0, count: fftSize / 2),
                                          sampleRate: sampleRate))
            analyzer.reset()
        }
        let frame = try XCTUnwrap(analyzer.consume(samples: [Float](repeating: 0, count: fftSize),
                                                  sampleRate: sampleRate))
        XCTAssertTrue(frame.bands.allSatisfy { $0 == 0 })
    }

    func testNonfiniteAndOversizedSamplesCannotPoisonFFT() throws {
        let analyzer = SpectrumAnalyzer(bandCount: 32)
        let invalid: [Float] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude,
                                -.greatestFiniteMagnitude, 0]
        let samples = (0..<fftSize).map { invalid[$0 % invalid.count] }
        let frame = try XCTUnwrap(analyzer.consume(samples: samples, sampleRate: sampleRate))
        XCTAssertEqual(frame.bands.count, 32)
        XCTAssertTrue(frame.bands.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertTrue(frame.rmsDB.isFinite)
        XCTAssertTrue(frame.peakFrequency.isFinite)
    }

    func testReleaseFallsSmoothlyAndResetRemovesHistory() throws {
        let analyzer = SpectrumAnalyzer()
        let loud = try XCTUnwrap(analyzer.consume(
            samples: sine(frequency: 1_500, amplitude: 1, count: fftSize * 8), sampleRate: sampleRate
        ))
        let fading = try XCTUnwrap(analyzer.consume(
            samples: [Float](repeating: 0, count: fftSize), sampleRate: sampleRate
        ))
        XCTAssertGreaterThan(fading.bands.max() ?? 0, 0)
        XCTAssertLessThan(fading.bands.max() ?? 0, loud.bands.max() ?? 0)
        let settled = try XCTUnwrap(analyzer.consume(
            samples: [Float](repeating: 0, count: Int(sampleRate * 3)), sampleRate: sampleRate
        ))
        XCTAssertTrue(settled.bands.allSatisfy { $0 == 0 })
        analyzer.reset()
        XCTAssertNil(analyzer.consume(samples: [Float](repeating: 0, count: fftSize / 2),
                                      sampleRate: sampleRate))
    }

    func testNyquistLimitsBandsAtLowerSampleRates() throws {
        let analyzer = SpectrumAnalyzer()
        let lowRate = 16_000.0
        let samples = sine(frequency: 6_000, amplitude: 0.25, count: fftSize * 5,
                           rate: lowRate)
        let frame = try XCTUnwrap(analyzer.consume(samples: samples, sampleRate: lowRate))
        XCTAssertEqual(frame.peakFrequency, 6_000, accuracy: 2)
        XCTAssertTrue(frame.bands.allSatisfy { $0.isFinite && (0...1).contains($0) })
        XCTAssertGreaterThan(frame.bands.suffix(8).max() ?? 0, 0.7)
    }

    func testOppositePhaseStereoRetainsMonoSpectrumAndRMS() throws {
        let mono = SpectrumAnalyzer()
        let stereo = SpectrumAnalyzer()
        let samples = sine(frequency: 1_500, amplitude: 0.5, count: fftSize * 6)
        let monoFrame = try XCTUnwrap(mono.consume(samples: samples, sampleRate: sampleRate))
        let stereoFrame = try XCTUnwrap(stereo.consume(
            channels: [samples, samples.map { -$0 }], sampleRate: sampleRate
        ))
        XCTAssertEqual(stereoFrame.rmsDB, monoFrame.rmsDB, accuracy: 0.001)
        XCTAssertEqual(stereoFrame.peakFrequency, monoFrame.peakFrequency, accuracy: 0.01)
        for (stereoBand, monoBand) in zip(stereoFrame.bands, monoFrame.bands) {
            XCTAssertEqual(stereoBand, monoBand, accuracy: 0.000_01)
        }
        XCTAssertGreaterThan(stereoFrame.bands.max() ?? 0, 0.9)
    }

    func testHardPannedStereoUsesMeanChannelPower() throws {
        let mono = SpectrumAnalyzer()
        let stereo = SpectrumAnalyzer()
        let samples = sine(frequency: 1_500, amplitude: 0.5, count: fftSize * 8)
        let monoFrame = try XCTUnwrap(mono.consume(samples: samples, sampleRate: sampleRate))
        let stereoFrame = try XCTUnwrap(stereo.consume(
            channels: [samples, [Float](repeating: 0, count: samples.count)], sampleRate: sampleRate
        ))
        // One silent channel halves power, giving a 3.0103 dB reduction.
        XCTAssertEqual(monoFrame.rmsDB - stereoFrame.rmsDB, 3.0103, accuracy: 0.001)
        XCTAssertEqual((monoFrame.bands.max() ?? 0) - (stereoFrame.bands.max() ?? 0),
                       3.0103 / 80, accuracy: 0.001)
        XCTAssertEqual(stereoFrame.peakFrequency, 1_500, accuracy: 0.1)
    }

    func testStereoChunkBoundariesKeepChannelsAligned() throws {
        let left = sine(frequency: 750, amplitude: 0.3, count: fftSize * 4 + 177)
        let right = sine(frequency: 3_000, amplitude: 0.5, count: left.count)
        let continuous = SpectrumAnalyzer()
        let expected = try XCTUnwrap(continuous.consume(channels: [left, right], sampleRate: sampleRate))
        let chunked = SpectrumAnalyzer()
        var actual: SpectrumFrame?
        var offset = 0
        while offset < left.count {
            let end = min(left.count, offset + 713)
            if let frame = chunked.consume(
                channels: [Array(left[offset..<end]), Array(right[offset..<end])], sampleRate: sampleRate
            ) {
                actual = frame
            }
            offset = end
        }
        XCTAssertEqual(try XCTUnwrap(actual), expected)
    }

    func testInvalidChannelLayoutsDiscardBufferedAudio() throws {
        let analyzer = SpectrumAnalyzer()
        let partial = [Float](repeating: 1, count: fftSize / 2)
        _ = analyzer.consume(channels: [partial, partial], sampleRate: sampleRate)
        XCTAssertNil(analyzer.consume(channels: [[0], [0, 0]], sampleRate: sampleRate))
        let silence = [Float](repeating: 0, count: fftSize / 2)
        XCTAssertNil(analyzer.consume(channels: [silence, silence], sampleRate: sampleRate))
        XCTAssertNil(analyzer.consume(channels: [], sampleRate: sampleRate))
        XCTAssertNil(analyzer.consume(channels: [silence, silence], sampleRate: sampleRate))
        let frame = try XCTUnwrap(analyzer.consume(channels: [silence, silence], sampleRate: sampleRate))
        XCTAssertEqual(frame.rmsDB, -100)
        XCTAssertTrue(frame.bands.allSatisfy { $0 == 0 })
    }

    func testChannelCountChangeDiscardsPartialAudioAndSmoothing() throws {
        let analyzer = SpectrumAnalyzer()
        _ = analyzer.consume(samples: sine(frequency: 1_000, amplitude: 1, count: fftSize),
                             sampleRate: sampleRate)
        let silence = [Float](repeating: 0, count: fftSize / 2)
        XCTAssertNil(analyzer.consume(channels: [silence, silence], sampleRate: sampleRate))
        let frame = try XCTUnwrap(analyzer.consume(channels: [silence, silence], sampleRate: sampleRate))
        XCTAssertEqual(frame.rmsDB, -100)
        XCTAssertTrue(frame.bands.allSatisfy { $0 == 0 })
    }

    private func sine(frequency: Double, amplitude: Float, count: Int, rate: Double? = nil) -> [Float] {
        let rate = rate ?? sampleRate
        return (0..<count).map { index in
            amplitude * Float(sin(2 * Double.pi * frequency * Double(index) / rate))
        }
    }
}
