import XCTest
@testable import SpectrumCore

final class SpectrumDisplayResponseTests: XCTestCase {
    func testTwentyDecibelVolumeChangeCreatesPronouncedHeightDifference() throws {
        let quiet = try displayedPeak(amplitude: 0.01)
        let medium = try displayedPeak(amplitude: 0.1)

        // The previous square-root amplitude response gave only about 3.4x
        // height for this 20 dB change. Require a much more pronounced contrast.
        XCTAssertGreaterThan(quiet, 0)
        XCTAssertGreaterThan(medium, 0.3)
        XCTAssertGreaterThan(medium / quiet, 8)
    }

    func testOrdinaryLoudnessChangesDoNotBothSaturateAtDefaultSensitivity() throws {
        let medium = try displayedPeak(amplitude: 0.1)
        let loud = try displayedPeak(amplitude: 0.3)

        // Both tones used to reach full height at 1.4x sensitivity.
        XCTAssertGreaterThan(loud, 0.7)
        XCTAssertLessThan(loud, 1)
        XCTAssertGreaterThan(loud - medium, 0.4)
    }

    func testVolumeDropAndReturnProduceLargeHeightChangesInOneStream() throws {
        let analyzer = SpectrumAnalyzer()
        let loud = try XCTUnwrap(analyzer.consume(samples: sine(amplitude: 0.3, count: 4096 * 10),
                                                  sampleRate: 48_000))
        let quiet = try XCTUnwrap(analyzer.consume(samples: sine(amplitude: 0.01, count: 19_200),
                                                   sampleRate: 48_000))
        let returning = try XCTUnwrap(analyzer.consume(samples: sine(amplitude: 0.3, count: 8192),
                                                       sampleRate: 48_000))

        let loudHeight = try peakHeight(loud)
        let quietHeight = try peakHeight(quiet)
        let returningHeight = try peakHeight(returning)
        XCTAssertLessThan(quietHeight, loudHeight * 0.15)
        XCTAssertGreaterThan(returningHeight, 0.6)
        XCTAssertGreaterThan(returningHeight - quietHeight, 0.5)
    }

    private func displayedPeak(amplitude: Float) throws -> Double {
        let analyzer = SpectrumAnalyzer()
        let frame = try XCTUnwrap(analyzer.consume(samples: sine(amplitude: amplitude, count: 4096 * 10),
                                                   sampleRate: 48_000))
        return try peakHeight(frame)
    }

    private func peakHeight(_ frame: SpectrumFrame) throws -> Double {
        return try XCTUnwrap(SpectrumDisplayResponse.heights(for: frame.bands, sensitivity: 1.4).max())
    }

    private func sine(amplitude: Float, count: Int) -> [Float] {
        (0..<count).map { index in
            amplitude * Float(sin(2 * Double.pi * 1_500 * Double(index) / 48_000))
        }
    }
}
