import Foundation
import VitrineDomain
import VitrineRendering

/// Resolves the text that may enter history before a record or thumbnail is created.
/// This policy never changes the export that the user requested.
enum CaptureRetentionPolicy {
    enum Consent: Equatable {
        case doNotSave
        case saveSanitized
        case keepOriginal
    }

    enum Decision: Equatable {
        case omit
        case safe(String)
        case requiresConsent(original: String, sanitized: String)
    }

    static func decide(_ config: SnapshotConfig) -> Decision {
        // The code hidden behind an image is not the captured content.
        guard !config.usesImageContent else { return .omit }
        // Explicit redactions are irreversible here, even if the user later elects
        // to keep a heuristic match. Never offer the pre-redaction source as a choice.
        let retained = config.richClipboardText
        // Only an unredacted terminal transcript differs from its resolved screen.
        let visible =
            config.language == .terminal && config.redactedLineRanges.isEmpty
            ? config.sidecarText : retained
        let visibleMatches = SecretScanner.secretLines(in: visible)
        guard
            !visibleMatches.isEmpty
                || (retained != visible && !SecretScanner.scan(retained).isEmpty)
        else {
            return .safe(retained)
        }
        // A terminal transcript can contain overwritten/alternate-screen secrets.
        // Sanitized history keeps only resolved rows, not the original escape stream.
        var rows = visible.components(separatedBy: "\n")
        for line in visibleMatches where rows.indices.contains(line - 1) {
            rows[line - 1] = SnapshotConfig.redactedLinePlaceholder
        }
        return .requiresConsent(original: retained, sanitized: rows.joined(separator: "\n"))
    }
}
