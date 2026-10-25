import Foundation

/// Converts logarithmic analysis levels to the visual extent shared by every style.
public enum SpectrumDisplayResponse {
    public static func heights(for bands: [Float], sensitivity: Double) -> [Double] {
        let gain = sensitivity.isFinite ? max(0, sensitivity) : 0
        return bands.map { band in
            let level = band.isFinite ? min(1, max(0, Double(band))) : 0
            // Expand the analyzer's -80...0 dB scale towards square-root amplitude,
            // keeping quiet audio visible and more headroom for volume changes.
            // Apply sensitivity afterwards so ordinary levels do not all saturate.
            return min(1, (pow(100, level) - 1) / 99 * gain)
        }
    }
}
