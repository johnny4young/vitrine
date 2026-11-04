import Foundation
import VitrineDomain

/// What an export would carry that looks like a secret, checked on this Mac before the
/// export runs. Pure: it reports and never changes the document or stores its text.
public struct ExportPreflight: Equatable, Sendable {
    public enum Action: String, Sendable {
        case copy, save, share, export
    }

    public enum Location: Hashable, Sendable {
        /// Rendered rows, which a line redaction can cover.
        case lines(ClosedRange<Int>)
        /// Terminal output no longer on screen, which only a share link's transcript keeps.
        case terminalHistory
        /// Header, annotation or alternative text, which has no row to redact.
        case label
    }

    public struct Finding: Hashable, Sendable {
        public let location: Location
        public let kind: String

        public init(location: Location, kind: String) {
            self.location = location
            self.kind = kind
        }
    }

    public let findings: [Finding]
    public let redactableLines: [Int]
    private let contentHash: Int

    public var isClean: Bool { findings.isEmpty }

    /// Pass `carriesTranscript` for a share link: it is the only export that keeps an
    /// unredacted terminal transcript instead of the resolved screen.
    public init(_ config: SnapshotConfig, carriesTranscript: Bool = false) {
        var unredacted = config
        unredacted.redactedLineRanges = []
        // Scan past existing redactions so a hand-redacted PEM banner cannot hide the key
        // body below it, then report only rows that are still visible.
        let rows = unredacted.sidecarText
        let redactions = LineHighlight.normalize(config.redactedLineRanges)
        let visible = SecretScanner.scan(rows).filter {
            !LineHighlight.contains(redactions, line: $0.line)
        }
        let labels =
            [
                config.windowTitle, config.metadata.filename, config.metadata.title,
                config.metadata.caption, config.altText?.text,
            ].compactMap { $0 } + config.annotations.map(\.text)
        let includesTranscript =
            carriesTranscript && config.language == .terminal && redactions.isEmpty
            && visible.isEmpty
        let transcriptKinds =
            includesTranscript ? SecretScanner.scan(config.code).map(\.kind) : []

        findings =
            Self.groupedRows(visible)
            + Self.unique(transcriptKinds).map { Finding(location: .terminalHistory, kind: $0) }
            + Self.unique(labels.flatMap { SecretScanner.scan($0).map(\.kind) })
            .map { Finding(location: .label, kind: $0) }
        redactableLines = Array(Set(visible.map(\.line))).sorted()

        var hasher = Hasher()
        hasher.combine(rows)
        hasher.combine(labels)
        hasher.combine(includesTranscript ? config.code : "")
        hasher.combine(findings)
        contentHash = hasher.finalize()
    }

    /// The existing redactions plus every flagged row.
    public func redactions(adding existing: [ClosedRange<Int>]) -> [ClosedRange<Int>] {
        LineHighlight.normalize(existing + redactableLines.map { $0...$0 })
    }

    /// Identifies this content and destination so an unchanged "anyway" is not asked again.
    /// Valid for this process only, and irreversible, so it never retains the text.
    public func acknowledgement(for action: Action) -> Int {
        var hasher = Hasher()
        hasher.combine(contentHash)
        hasher.combine(action.rawValue)
        return hasher.finalize()
    }

    /// A private key spans many rows, so consecutive rows of one kind read as one finding.
    private static func groupedRows(_ matches: [SecretScanner.Match]) -> [Finding] {
        var groups: [(kind: String, first: Int, last: Int)] = []
        for match in matches {
            if let index = groups.lastIndex(where: { $0.kind == match.kind }),
                groups[index].last == match.line - 1
            {
                groups[index].last = match.line
            } else {
                groups.append((match.kind, match.line, match.line))
            }
        }
        return groups.map { Finding(location: .lines($0.first...$0.last), kind: $0.kind) }
    }

    private static func unique(_ kinds: [String]) -> [String] {
        var seen = Set<String>()
        return kinds.filter { seen.insert($0).inserted }
    }
}
