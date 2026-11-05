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

        var inspection: ClipboardInspector.Inspection {
            guard ClipboardInspector.content(types: types) == .text(nil) else { return .none }
            return ClipboardInspector.inspection(access: access, types: types)
        }
    }

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let reader: ClipboardReader
    @ObservationIgnored private let watchInterval: Duration
    @ObservationIgnored private var inspected: InspectedClipboard?
    @ObservationIgnored private var inspection: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard = .general, reader: ClipboardReader = .live,
        watchInterval: Duration = .seconds(1)
    ) {
        self.pasteboard = pasteboard
        self.reader = reader
        self.watchInterval = watchInterval
    }

    func refresh(
        hotkeyAction: HotkeyAction,
        shortcut: KeyboardShortcuts.Shortcut? = KeyboardShortcuts.getShortcut(for: .quickCapture)
    ) {
        hotkeyGlyphs = shortcut?.description
        hotkeyPurpose = Self.hotkeyPurpose(for: hotkeyAction)
    }

    /// Updates what the pasteboard's types reveal right away, then inspects any text in the
    /// background. A measurement keeps the previous facts on screen until it arrives.
    func refreshClipboard(access: NSPasteboard.AccessBehavior? = nil) {
        // Writers bump the change count when clearing, before adding types, so a refresh
        // between the two steps must not hide what arrives next.
        let source = InspectedClipboard(
            changeCount: pasteboard.changeCount,
            access: access ?? pasteboard.accessBehavior,
            types: pasteboard.types?.map(\.rawValue) ?? [])
        guard source != inspected else {
            // A slow read must not leave the previous clipboard's facts on screen.
            if inspection != nil, case .text = clipboard { clipboard = .text(nil) }
            return
        }
        inspected = source

        let known = ClipboardInspector.content(types: source.types)
        if source.inspection != .read || !clipboardHasFacts { clipboard = known }
        if source.inspection != .none { startInspection() }
    }

    private var clipboardHasFacts: Bool {
        if case .text(.some) = clipboard { return true }
        return false
    }

    /// Runs one inspection at a time. A result for an older clipboard is discarded, and the
    /// latest clipboard is inspected next.
    private func startInspection() {
        guard inspection == nil, let target = inspected else { return }
        let name = pasteboard.name
        inspection = Task { [weak self, reader] in
            let result: ClipboardContent?
            if target.inspection == .read {
                result = await reader.read(name, target.changeCount)
            } else {
                let isURL = await reader.detectsWebURL(name, target.changeCount)
                result = isURL ? .possibleWebURL : nil
            }
            guard let self else { return }
            inspection = nil
            guard target == inspected else {
                if inspected?.inspection != ClipboardInspector.Inspection.none {
                    startInspection()
                }
                return
            }
            clipboard = result ?? .text(nil)
        }
    }

    /// Finishes once every inspection started so far has been applied.
    func clipboardInspectionFinished() async {
        while let inspection { await inspection.value }
    }

    /// The panel stays open after its own Copy actions, so it follows the change count and
    /// types, which read no content, for as long as it is on screen.
    func startWatchingClipboard() {
        watcher?.cancel()
        let interval = watchInterval
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval, tolerance: interval / 4)
                guard !Task.isCancelled, let self else { return }
                refreshClipboard()
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
