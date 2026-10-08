import Foundation
import KeyboardShortcuts
import Observation
import VitrineDomain

/// Panel state that SwiftUI cannot observe on its own. The popover is reused, so the
/// status-item controller refreshes it every time the panel opens.
@Observable
final class MenuBarPanelState {
    /// The recorded global shortcut as glyphs, or `nil` when none is set.
    private(set) var hotkeyGlyphs: String?
    /// What the global shortcut does, read aloud with the glyphs.
    private(set) var hotkeyPurpose = MenuBarPanelState.hotkeyPurpose(for: .fallback)

    func refresh(
        hotkeyAction: HotkeyAction,
        shortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(for: .quickCapture)
    ) {
        hotkeyGlyphs = shortcut?.description
        hotkeyPurpose = Self.hotkeyPurpose(for: hotkeyAction)
    }

    static func hotkeyPurpose(for action: HotkeyAction) -> String {
        switch action {
        case .quickCapture: String(localized: "Capture hotkey")
        case .openEditor: String(localized: "Editor hotkey")
        }
    }
}
