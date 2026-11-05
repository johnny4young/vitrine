import AppKit
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// What the next capture would find on the clipboard, as far as the panel may know.
nonisolated enum ClipboardContent: Equatable, Sendable {
    /// Nothing a capture can use.
    case nothing
    case image
    /// Unread text the system says holds a web URL, which may also be code containing one.
    case possibleWebURL
    /// Text, with `nil` facts when its contents are unread or too large to measure.
    case text(ClipboardTextFacts?)
}

/// Measurements of clipboard text. Never holds the text itself.
nonisolated struct ClipboardTextFacts: Equatable, Sendable {
    var language: Language
    var lineCount: Int
    var blockCount = 0
    var isURL = false
}

/// The one-line preview under the capture button.
nonisolated struct MenuBarCaptureSummary: Equatable {
    var line: String
    /// The fallback when `line` does not fit the panel, so the destination stays whole.
    var lineWithoutTheme: String
    var accessibilityLabel: String

    /// Follows `QuickCapture.perform`: an image ignores the theme, a URL it would open in
    /// Web Snapshot uses no style, and the editor hand-offs may not keep the destination.
    static func make(
        content: ClipboardContent,
        themeName: String,
        destination: ExportPreset?,
        capturesURLs: Bool,
        bundle: Bundle = .main
    ) -> MenuBarCaptureSummary? {
        switch content {
        case .nothing:
            return nil
        case .image:
            return text(lead: [String(localized: "Image", bundle: bundle)], bundle: bundle)
        case .possibleWebURL where capturesURLs:
            // Could open Web Snapshot or render as code, and only a read can tell.
            return nil
        case .possibleWebURL, .text(nil):
            guard destination != nil else { return nil }
            return text(theme: themeName, destination: destination, bundle: bundle)
        case .text(let facts?):
            if facts.isURL, capturesURLs { return webSnapshot(bundle: bundle) }
            return text(
                lead: details(of: facts, bundle: bundle), theme: themeName,
                destination: facts.blockCount > 1 ? nil : destination, bundle: bundle)
        }
    }

    private static func webSnapshot(bundle: Bundle) -> MenuBarCaptureSummary {
        text(lead: [String(localized: "Web Snapshot", bundle: bundle)], bundle: bundle)
    }

    private static func text(
        lead: [String] = [], theme: String? = nil, destination: ExportPreset? = nil, bundle: Bundle
    ) -> MenuBarCaptureSummary {
        let shown = destination.map(destinationLabel(for:)).map { [$0] } ?? []
        let spoken =
            destination.map { spokenDestination(for: $0, bundle: bundle) }.map { [$0] } ?? []
        let style = theme.map { [$0] } ?? []
        return MenuBarCaptureSummary(
            line: (lead + style + shown).joined(separator: " · "),
            lineWithoutTheme: (lead + shown).joined(separator: " · "),
            accessibilityLabel: (lead + style + spoken).joined(separator: ", "))
    }

    private static func details(of facts: ClipboardTextFacts, bundle: Bundle) -> [String] {
        let count = facts.blockCount > 1 ? facts.blockCount : facts.lineCount
        let measure =
            facts.blockCount > 1
            ? String(localized: "\(count) code blocks", bundle: bundle)
            : String(localized: "\(count) lines", bundle: bundle)
        return [facts.language.displayName, measure]
    }

    /// Some preset names already carry their size, so it is removed before the size is added.
    static func destinationLabel(for preset: ExportPreset) -> String {
        guard let (width, height) = pixels(of: preset) else { return preset.displayName }
        return "\(presetName(preset, width: width, height: height)) \(width) × \(height)"
    }

    private static func spokenDestination(for preset: ExportPreset, bundle: Bundle) -> String {
        guard let (width, height) = pixels(of: preset) else { return preset.displayName }
        let size = String(localized: "\(width) by \(height)", bundle: bundle)
        return "\(presetName(preset, width: width, height: height)) \(size)"
    }

    private static func pixels(of preset: ExportPreset) -> (Int, Int)? {
        preset.sizing.fixedSize.map { (Int($0.width), Int($0.height)) }
    }

    private static func presetName(_ preset: ExportPreset, width: Int, height: Int) -> String {
        preset.displayName
            .replacingOccurrences(of: "\(width)×\(height)", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Decides what the panel may learn about the clipboard, and measures it away from the
/// Swift concurrency pool.
nonisolated enum ClipboardInspector {
    /// Above this the text is not decoded, so the summary shows no language or line count.
    static let maximumMeasuredBytes = 256 * 1024

    /// Marks for content not meant to linger, plus remote clipboards, whose data arrives
    /// over the network and could hold the read queue.
    private static let unreadableMarkers: Set<String> = [
        ClipboardWriter.concealedType.rawValue,
        "org.nspasteboard.TransientType",
        "de.petermaurer.TransientPasteboardType",
        "com.agilebits.onepassword",
        "net.antelle.keeweb",
        "com.apple.is-remote-clipboard",
    ]

    /// A pasteboard read blocks on the owning process, so it never occupies a Swift
    /// concurrency thread, and queued reads cannot run side by side.
    private static let readQueue = DispatchQueue(
        label: "com.johnny4young.vitrine.menu-bar-clipboard", qos: .userInitiated)

    /// Listing types does not read content. An image wins over text, as it does when capturing.
    static func content(types: [String]) -> ClipboardContent {
        if types.contains(where: { UTType($0)?.conforms(to: .image) == true }) { return .image }
        return types.contains(NSPasteboard.PasteboardType.string.rawValue) ? .text(nil) : .nothing
    }

    enum Inspection: Equatable {
        case read
        case detectWebURL
        case none
    }

    /// Opening the panel is not a paste, so contents are read only under Always Allow. Other
    /// behaviors get the documented silent pattern check. Marked content gets neither.
    static func inspection(
        access: NSPasteboard.AccessBehavior, types: [String]
    ) -> Inspection {
        guard unreadableMarkers.isDisjoint(with: types) else { return .none }
        return access == .alwaysAllow ? .read : .detectWebURL
    }

    /// Oversized or undecodable text stays unmeasured, so no number disagrees with the capture.
    static func content(ofUTF8 data: Data) -> ClipboardContent {
        guard data.count <= maximumMeasuredBytes,
            let text = String(data: data, encoding: .utf8)
        else { return .text(nil) }
        return facts(of: text).map { .text($0) } ?? .nothing
    }

    /// `nil` for blank text, which a capture treats as an empty clipboard.
    static func facts(of text: String) -> ClipboardTextFacts? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let interpreted = LanguageDetector.interpret(text)
        return ClipboardTextFacts(
            language: interpreted.language,
            lineCount: LineSplitter.lineCount(of: interpreted.code),
            blockCount: interpreted.blockCount,
            isURL: LanguageDetector.isURL(text))
    }

    /// `nil` when the pasteboard moved on or became marked around the read.
    static func readContent(
        from name: NSPasteboard.Name, expecting changeCount: Int
    ) async -> ClipboardContent? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: readNow(from: name, expecting: changeCount))
            }
        }
    }

    private static func readNow(
        from name: NSPasteboard.Name, expecting changeCount: Int
    ) -> ClipboardContent? {
        let pasteboard = NSPasteboard(name: name)
        guard isReadable(pasteboard, expecting: changeCount) else { return nil }
        let data = pasteboard.data(forType: .string)
        guard isReadable(pasteboard, expecting: changeCount) else { return nil }
        return data.map(content(ofUTF8:)) ?? .nothing
    }

    private static func isReadable(_ pasteboard: NSPasteboard, expecting changeCount: Int) -> Bool {
        pasteboard.changeCount == changeCount
            && unreadableMarkers.isDisjoint(with: pasteboard.types?.map(\.rawValue) ?? [])
    }

    /// The header documents this check as silent: it reports a match without the contents.
    @concurrent static func detectsWebURL(
        on name: NSPasteboard.Name, expecting changeCount: Int
    ) async -> Bool {
        let pasteboard = NSPasteboard(name: name)
        let pattern: PartialKeyPath<NSPasteboard.DetectedValues> = \.probableWebURL
        let matches = try? await pasteboard.detectedPatterns(for: [pattern])
        return matches?.contains(pattern) == true && pasteboard.changeCount == changeCount
    }
}

/// The two operations that touch pasteboard contents, injectable so tests can hold them open.
nonisolated struct ClipboardReader: Sendable {
    var read: @Sendable (NSPasteboard.Name, Int) async -> ClipboardContent?
    var detectsWebURL: @Sendable (NSPasteboard.Name, Int) async -> Bool

    static let live = ClipboardReader(
        read: { await ClipboardInspector.readContent(from: $0, expecting: $1) },
        detectsWebURL: { await ClipboardInspector.detectsWebURL(on: $0, expecting: $1) })
}
