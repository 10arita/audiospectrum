import Foundation

/// Converts logarithmic analysis levels to the visual extent shared by every style.
public enum SpectrumDisplayResponse {
    public static func heights(for bands: [Float], sensitivity: Double) -> [Double] {
        let gain = sensitivity.isFinite ? max(0, sensitivity) : 0
        return bands.map { band in
            let level = band.isFinite ? min(1, max(0, Double(band))) : 0
            // Recover linear amplitude from the analyzer's -80...0 dB scale,
            // then emphasize volume contrast so quiet sections shrink clearly.
            let amplitude = (pow(10_000, level) - 1) / 9_999
            let drivenAmplitude = pow(amplitude, 1.15) * gain
            // Soft saturation makes loud peaks expand without a flat ceiling
            // that would hide further changes in volume.
            return -expm1(-4 * drivenAmplitude)
        }
    }
}
