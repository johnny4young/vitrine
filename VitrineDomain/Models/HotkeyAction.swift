import Foundation

/// What the global hotkey triggers.
public enum HotkeyAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case quickCapture
    case openEditor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .quickCapture: "Quick capture from clipboard"
        case .openEditor: "Open the editor"
        }
    }

    /// The value used when nothing is persisted or a stored string no longer
    /// maps to a case (documented fallback).
    public static let fallback: HotkeyAction = .quickCapture

    /// Decodes a persisted raw value, tolerating `nil` or an unrecognized
    /// string by returning `fallback`.
    public static func resolve(_ rawValue: String?) -> HotkeyAction {
        HotkeyAction(rawValue: rawValue ?? "") ?? fallback
    }
}
