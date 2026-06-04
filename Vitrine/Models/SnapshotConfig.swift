import SwiftUI

/// Everything that defines the final image. This is the single source of truth
/// shared by the editor preview, the quick-capture path, and the exporter.
struct SnapshotConfig: Equatable {
    var code: String = ""
    var language: Language = .swift
    var theme: Theme = .oneDark
    var fontName: String = "JetBrains Mono"
    var fontSize: Double = 14
    var padding: Double = 32
    var background: BackgroundStyle = .gradient(.ocean)
    var showChrome: Bool = true
    var cornerRadius: Double = 8
    var shadowRadius: Double = 20
}

/// The canvas background style.
enum BackgroundStyle: Equatable, Hashable {
    case solid(Color)
    case gradient(GradientPreset)
    case transparent
}

/// Built-in gradient presets used as canvas backgrounds.
enum GradientPreset: String, CaseIterable, Identifiable {
    case ocean = "Ocean"
    case sunset = "Sunset"
    case forest = "Forest"
    case night = "Night"
    case carbon = "Carbon"

    var id: String { rawValue }

    /// Stop colors, top-leading → bottom-trailing.
    var colors: [Color] {
        switch self {
        case .ocean: [Color(hex: "#2E3192"), Color(hex: "#1BFFFF")]
        case .sunset: [Color(hex: "#FF512F"), Color(hex: "#F09819")]
        case .forest: [Color(hex: "#11998E"), Color(hex: "#38EF7D")]
        case .night: [Color(hex: "#0F2027"), Color(hex: "#2C5364")]
        case .carbon: [Color(hex: "#1F1C2C"), Color(hex: "#928DAB")]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
