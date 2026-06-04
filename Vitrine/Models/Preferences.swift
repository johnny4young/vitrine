import Foundation

/// What the global hotkey triggers (CS-002).
enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case quickCapture
    case openEditor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .quickCapture: "Quick capture from clipboard"
        case .openEditor: "Open the editor"
        }
    }
}

/// Exported image format (CS-010 · Output).
enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case pdf

    var id: String { rawValue }
    var displayName: String { self == .png ? "PNG" : "PDF" }
}
