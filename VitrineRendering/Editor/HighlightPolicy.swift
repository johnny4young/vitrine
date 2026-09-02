import Foundation
import VitrineDomain

/// The syntax-highlighting work Vitrine will perform for one source document.
public enum HighlightMode: Equatable {
    case full
    case plainTextFallback(actualBytes: Int, maximumBytes: Int)

    nonisolated public var usesPlainTextFallback: Bool {
        if case .plainTextFallback = self { return true }
        return false
    }
}

/// Central memory and responsiveness policy for syntax highlighting.
///
/// Source import intentionally accepts up to 5 MB, but feeding that entire ceiling through a
/// JavaScript tokenizer and several attributed-string bridges on the main actor is not an
/// interactive-safe contract. Documents above the highlighting ceiling remain fully editable and
/// renderable using legible plain text. Medium documents still receive syntax colors, but bypass
/// every derived-output cache and use a longer trailing debounce while the user types.
public enum HighlightPolicy {
    /// Largest source sent through Highlight.js. This is already far beyond a practical code-card
    /// snippet while bounding synchronous tokenization and bridge amplification on the main actor.
    nonisolated public static let maximumHighlightedByteCount = 128 * 1024

    /// Documents above this size are never retained by a highlighting cache. A cache hit is most
    /// valuable for screenshot-sized snippets; retaining large documents across multiple derived
    /// representations would trade a small speed-up for disproportionate memory pressure.
    nonisolated public static let maximumCacheableByteCount = 32 * 1024

    /// Each representation owns this conservative estimated-cost budget. `HighlightManager`
    /// keeps five representation caches, so their aggregate estimate stays at or below 20 MiB.
    nonisolated public static let perRepresentationCostLimit = 4 * 1024 * 1024
    nonisolated public static let countLimit = 8

    public enum Representation {
        case attributedString
        case swiftUIAttributedString
        case attributedLines
        case terminalAttributedString
        case terminalAttributedLines

        fileprivate nonisolated var amplification: Int {
            switch self {
            case .attributedString: 8
            case .swiftUIAttributedString, .terminalAttributedString: 10
            case .attributedLines, .terminalAttributedLines: 12
            }
        }
    }

    nonisolated public static func mode(for code: String, language: Language) -> HighlightMode {
        // Terminal captures use a separate bounded parser/emulator rather than Highlight.js.
        // Its large-input lifecycle belongs to the dedicated terminal reliability band.
        guard language != .terminal else { return .full }
        let bytes = byteCount(of: code)
        guard bytes > maximumHighlightedByteCount else { return .full }
        return .plainTextFallback(
            actualBytes: bytes, maximumBytes: maximumHighlightedByteCount)
    }

    nonisolated public static func shouldCache(_ code: String) -> Bool {
        byteCount(of: code) <= maximumCacheableByteCount
    }

    /// Normal snippets keep the existing 100 ms editor debounce. Medium documents use a longer
    /// quiet window so a typing burst is less likely to start repeated full tokenizations.
    nonisolated public static func editorDebounce(for code: String) -> Duration {
        shouldCache(code) ? .milliseconds(100) : .milliseconds(250)
    }

    nonisolated public static func previewDebounce(for code: String) -> Duration {
        shouldCache(code) ? .milliseconds(90) : .milliseconds(250)
    }

    /// A conservative cost estimate for one derived representation. Overflow becomes `Int.max`,
    /// which the cache rejects as larger than its budget.
    nonisolated public static func cacheCost(
        for code: String, representation: Representation
    ) -> Int {
        let (utf16Bytes, utf16Overflow) = code.utf16.count.multipliedReportingOverflow(
            by: MemoryLayout<UInt16>.stride)
        guard !utf16Overflow else { return .max }
        let bytes = max(byteCount(of: code), utf16Bytes)
        let (amplified, multipliedOverflow) = bytes.multipliedReportingOverflow(
            by: representation.amplification)
        guard !multipliedOverflow else { return .max }
        let (cost, addedOverflow) = amplified.addingReportingOverflow(1024)
        return addedOverflow ? .max : cost
    }

    nonisolated public static func byteCount(of code: String) -> Int { code.utf8.count }
}
