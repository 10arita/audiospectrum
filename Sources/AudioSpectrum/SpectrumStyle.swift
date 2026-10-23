import SwiftUI

enum SpectrumStyle: String, CaseIterable, Identifiable {
    case circular, mirrored, bottom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .circular: return "円形"
        case .mirrored: return "バー・中央"
        case .bottom: return "バー・底"
        }
    }
    var subtitle: String {
        switch self {
        case .circular: return "円周から外側へ"
        case .mirrored: return "中央から上下へ"
        case .bottom: return "底から上へ"
        }
    }
    var symbol: String {
        switch self {
        case .circular: return "circle.dotted"
        case .mirrored: return "waveform"
        case .bottom: return "chart.bar.xaxis"
        }
    }
}

enum SpectrumPalette: String, CaseIterable, Identifiable {
    case mint, blue, amber
    var id: String { rawValue }
    var title: String {
        switch self { case .mint: return "ミント"; case .blue: return "ブルー"; case .amber: return "アンバー" }
    }
    var colors: [Color] {
        switch self {
        case .mint: return [Color(red: 0.26, green: 0.94, blue: 0.73), Color(red: 0.37, green: 0.73, blue: 1)]
        case .blue: return [Color(red: 0.35, green: 0.65, blue: 1), Color(red: 0.72, green: 0.63, blue: 1)]
        case .amber: return [Color(red: 1, green: 0.78, blue: 0.30), Color(red: 1, green: 0.48, blue: 0.40)]
        }
    }
    var accent: Color { colors[0] }
}

enum SpectrumTheme {
    static let background = Color(red: 0.055, green: 0.065, blue: 0.08)
    static let surface = Color(red: 0.08, green: 0.095, blue: 0.115)
    static let secondary = Color(red: 0.65, green: 0.70, blue: 0.76)
    static let line = Color.white.opacity(0.10)
}
