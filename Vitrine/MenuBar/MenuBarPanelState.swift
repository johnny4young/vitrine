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
    /// What the capture button would pick up. Holds measurements, never clipboard text.
    private(set) var clipboard = ClipboardContent.nothing

    private struct InspectedClipboard: Equatable {
        let changeCount: Int
        let access: NSPasteboard.AccessBehavior
        let types: [String]
    }

    @ObservationIgnored private var inspected: InspectedClipboard?
    @ObservationIgnored private var inspection: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?

    func refresh(
        hotkeyAction: HotkeyAction,
        shortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(for: .quickCapture)
    ) {
        hotkeyGlyphs = shortcut?.description
        hotkeyPurpose = Self.hotkeyPurpose(for: hotkeyAction)
    }

    /// Updates the known content from the pasteboard's types right away, then measures
    /// any text off the main actor, since a large or promised clipboard can be slow to read.
    func refreshClipboard(
        pasteboard: NSPasteboard = .general, access: NSPasteboard.AccessBehavior? = nil
    ) {
        // Writers bump the change count when clearing, before adding types, so a refresh
        // between the two steps must not hide what arrives next.
        let source = InspectedClipboard(
            changeCount: pasteboard.changeCount,
            access: access ?? pasteboard.accessBehavior,
            types: pasteboard.types?.map(\.rawValue) ?? [])
        guard source != inspected else { return }
        inspected = source
        inspection?.cancel()
        inspection = nil

        clipboard = ClipboardInspector.content(types: source.types)
        guard clipboard == .text(nil),
            ClipboardInspector.mayReadContents(access: source.access, types: source.types)
        else { return }

        let name = pasteboard.name
        inspection = Task { [weak self] in
            let content = await ClipboardInspector.readContent(from: name)
            guard !Task.isCancelled else { return }
            self?.clipboard = content
        }
    }

    /// Finishes once the measurement started by the latest refresh has been applied.
    func clipboardInspectionFinished() async {
        await inspection?.value
    }

    /// The panel stays open after its own Copy actions, so it follows the change count,
    /// which reads no content, for as long as it is on screen.
    func startWatchingClipboard() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.refreshClipboard()
            }
        }
    }

    func stopWatchingClipboard() {
        watcher?.cancel()
        watcher = nil
    }

    static func hotkeyPurpose(for action: HotkeyAction) -> String {
        switch action {
        case .quickCapture: String(localized: "Capture hotkey")
        case .openEditor: String(localized: "Editor hotkey")
        }
    }
}
