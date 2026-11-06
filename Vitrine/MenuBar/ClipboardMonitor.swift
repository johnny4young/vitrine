import AppKit
import Observation

/// What a surface may currently know about the clipboard, following the access rules in
/// ``ClipboardInspector``. Holds measurements, never clipboard text.
@Observable
final class ClipboardMonitor {
    private(set) var clipboard = ClipboardContent.nothing

    private struct InspectedClipboard: Equatable {
        let changeCount: Int
        let access: NSPasteboard.AccessBehavior
        let types: [String]
        let detectsWebURLs: Bool

        var inspection: ClipboardInspector.Inspection {
            guard ClipboardInspector.content(types: types) == .text(nil) else { return .none }
            let inspection = ClipboardInspector.inspection(access: access, types: types)
            return inspection == .detectWebURL && !detectsWebURLs ? .none : inspection
        }
    }

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let reader: ClipboardReader
    @ObservationIgnored private let watchInterval: Duration
    @ObservationIgnored private let detectsWebURLs: Bool
    @ObservationIgnored private var inspected: InspectedClipboard?
    @ObservationIgnored private var inspection: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?

    init(
        pasteboard: NSPasteboard = .general, reader: ClipboardReader = .live,
        watchInterval: Duration = .seconds(1), detectsWebURLs: Bool = true
    ) {
        self.pasteboard = pasteboard
        self.reader = reader
        self.watchInterval = watchInterval
        self.detectsWebURLs = detectsWebURLs
    }

    /// Updates what the pasteboard's types reveal right away, then inspects any text in the
    /// background. A measurement keeps the previous facts on screen until it arrives.
    func refresh(access: NSPasteboard.AccessBehavior? = nil) {
        // Writers bump the change count when clearing, before adding types, so a refresh
        // between the two steps must not hide what arrives next.
        let source = currentClipboard(access: access)
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

    private func currentClipboard(access: NSPasteboard.AccessBehavior?) -> InspectedClipboard {
        InspectedClipboard(
            changeCount: pasteboard.changeCount,
            access: access ?? pasteboard.accessBehavior,
            types: pasteboard.types?.map(\.rawValue) ?? [],
            detectsWebURLs: detectsWebURLs)
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
    func inspectionFinished() async {
        while let inspection { await inspection.value }
    }

    /// Follows the change count and types, which read no content, until stopped.
    func startWatching() {
        watcher?.cancel()
        let interval = watchInterval
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval, tolerance: interval / 4)
                guard !Task.isCancelled, let self else { return }
                refresh()
            }
        }
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    /// Picks up after `stopWatching()`. An unchanged clipboard keeps its measurement and is
    /// not read again; a changed one drops it, so the old facts never reappear.
    func resumeWatching(access: NSPasteboard.AccessBehavior? = nil) {
        if currentClipboard(access: access) != inspected { clipboard = .nothing }
        refresh(access: access)
        startWatching()
    }
}
