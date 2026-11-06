import AppKit
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
    /// What the capture button would pick up.
    var clipboard: ClipboardContent { clipboardMonitor.clipboard }

    @ObservationIgnored private let clipboardMonitor: ClipboardMonitor

    init(
        pasteboard: NSPasteboard = .general, reader: ClipboardReader = .live,
        watchInterval: Duration = .seconds(1)
    ) {
        clipboardMonitor = ClipboardMonitor(
            pasteboard: pasteboard, reader: reader, watchInterval: watchInterval)
    }

    func refresh(
        hotkeyAction: HotkeyAction,
        shortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(for: .quickCapture)
    ) {
        hotkeyGlyphs = shortcut?.description
        hotkeyPurpose = Self.hotkeyPurpose(for: hotkeyAction)
    }

    func refreshClipboard(access: NSPasteboard.AccessBehavior? = nil) {
        clipboardMonitor.refresh(access: access)
    }

    /// Finishes once every inspection started so far has been applied.
    func clipboardInspectionFinished() async {
        await clipboardMonitor.inspectionFinished()
    }

    /// The panel stays open after its own Copy actions, so it follows the clipboard for as
    /// long as it is on screen.
    func startWatchingClipboard() {
        clipboardMonitor.startWatching()
    }

    func stopWatchingClipboard() {
        clipboardMonitor.stopWatching()
    }

    static func hotkeyPurpose(for action: HotkeyAction) -> String {
        switch action {
        case .quickCapture: String(localized: "Capture hotkey")
        case .openEditor: String(localized: "Editor hotkey")
        }
    }
}
