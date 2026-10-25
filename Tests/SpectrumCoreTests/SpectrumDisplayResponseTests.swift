import XCTest
@testable import SpectrumCore

final class SpectrumDisplayResponseTests: XCTestCase {
    func testTwentyDecibelVolumeChangeCreatesPronouncedHeightDifference() throws {
        let quiet = try displayedPeak(amplitude: 0.01)
        let medium = try displayedPeak(amplitude: 0.1)

        // With the previous direct dB mapping these heights were about 70% and
        // 100%, hiding most of the volume change. Keep a visibly wider contrast.
        XCTAssertGreaterThan(quiet, 0)
        XCTAssertGreaterThan(medium, 0.4)
        XCTAssertGreaterThan(medium / quiet, 2.5)
    }

    func testOrdinaryLoudnessChangesDoNotBothSaturateAtDefaultSensitivity() throws {
        let medium = try displayedPeak(amplitude: 0.1)
        let loud = try displayedPeak(amplitude: 0.3)

        // Both tones used to reach full height at 1.4x sensitivity.
        XCTAssertGreaterThan(loud, 0.7)
        XCTAssertLessThan(loud, 1)
        XCTAssertGreaterThan(loud - medium, 0.25)
    }

    private func displayedPeak(amplitude: Float) throws -> Double {
        let analyzer = SpectrumAnalyzer()
        let sampleRate = 48_000.0
        let samples = (0..<(4096 * 10)).map { index in
            amplitude * Float(sin(2 * Double.pi * 1_500 * Double(index) / sampleRate))
        }
        let frame = try XCTUnwrap(analyzer.consume(samples: samples, sampleRate: sampleRate))
        return try XCTUnwrap(SpectrumDisplayResponse.heights(for: frame.bands, sensitivity: 1.4).max())
    }
}
