import AppKit
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// What the next capture would find on the clipboard, as far as the panel may know.
nonisolated enum ClipboardContent: Equatable, Sendable {
    /// Nothing a capture can use.
    case nothing
    case image
    /// Text, with `nil` facts while its contents may not or have not been read.
    case text(ClipboardTextFacts?)
}

/// Measurements of clipboard text. Never holds the text itself.
nonisolated struct ClipboardTextFacts: Equatable, Sendable {
    /// `nil` when the text is too large to score while the panel opens.
    var language: Language?
    var lineCount: Int
    var blockCount = 0
    var isURL = false
}

/// The one-line preview under the capture button.
nonisolated enum MenuBarCaptureSummary {
    /// Follows `QuickCapture.perform`: an image ignores the theme, and a URL it would
    /// open in Web Snapshot uses neither the theme nor the destination.
    static func line(
        content: ClipboardContent,
        themeName: String,
        destination: ExportPreset?,
        capturesURLs: Bool,
        bundle: Bundle = .main
    ) -> String? {
        var parts: [String]
        switch content {
        case .nothing:
            return nil
        case .image:
            parts = [String(localized: "Image", bundle: bundle)]
        case .text(let facts):
            if let facts, facts.isURL, capturesURLs {
                return String(localized: "Web Snapshot", bundle: bundle)
            }
            parts = facts.map { details(of: $0, bundle: bundle) } ?? []
            parts.append(themeName)
        }
        if let destination { parts.append(destinationLabel(for: destination)) }
        return parts.joined(separator: " · ")
    }

    private static func details(of facts: ClipboardTextFacts, bundle: Bundle) -> [String] {
        let count = facts.blockCount > 1 ? facts.blockCount : facts.lineCount
        let measure =
            facts.blockCount > 1
            ? String(localized: "\(count) code blocks", bundle: bundle)
            : String(localized: "\(count) lines", bundle: bundle)
        return [facts.language?.displayName, measure].compactMap(\.self)
    }

    /// Some preset names already carry their size, so it is removed before the size is added.
    static func destinationLabel(for preset: ExportPreset) -> String {
        guard let size = preset.sizing.fixedSize else { return preset.displayName }
        let (width, height) = (Int(size.width), Int(size.height))
        let name = preset.displayName
            .replacingOccurrences(of: "\(width)×\(height)", with: "")
            .trimmingCharacters(in: .whitespaces)
        return "\(name) \(width) × \(height)"
    }
}

/// Decides what the panel may learn about the clipboard, and measures it off the main actor.
nonisolated enum ClipboardInspector {
    /// Above this, language scoring is skipped rather than guessed from a prefix the
    /// capture would not use.
    static let maximumScoredBytes = 256 * 1024

    /// Marks clipboard managers and password managers use for content not meant to linger.
    private static let privateMarkers: Set<String> = [
        ClipboardWriter.concealedType.rawValue, "org.nspasteboard.TransientType",
    ]

    /// Listing types does not read content, so it never raises the system paste alert.
    /// An image wins over text, as it does when capturing.
    static func content(types: [String]) -> ClipboardContent {
        if types.contains(where: { UTType($0)?.conforms(to: .image) == true }) { return .image }
        return types.contains(NSPasteboard.PasteboardType.string.rawValue) ? .text(nil) : .nothing
    }

    /// Opening the panel is not a paste, so a read is only silent when the user chose
    /// Always Allow. Every other behavior would raise the alert or be refused.
    static func mayReadContents(access: NSPasteboard.AccessBehavior, types: [String]) -> Bool {
        access == .alwaysAllow && privateMarkers.isDisjoint(with: types)
    }

    /// `nil` for blank text, which a capture treats as an empty clipboard.
    static func facts(of text: String) -> ClipboardTextFacts? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard text.utf8.count <= maximumScoredBytes else {
            return ClipboardTextFacts(language: nil, lineCount: LineSplitter.lineCount(of: text))
        }
        let interpreted = LanguageDetector.interpret(text)
        return ClipboardTextFacts(
            language: interpreted.language,
            lineCount: LineSplitter.lineCount(of: interpreted.code),
            blockCount: interpreted.blockCount,
            isURL: LanguageDetector.isURL(text))
    }

    @concurrent static func readContent(from name: NSPasteboard.Name) async -> ClipboardContent {
        guard let text = NSPasteboard(name: name).string(forType: .string),
            let facts = facts(of: text)
        else { return .nothing }
        return .text(facts)
    }
}
