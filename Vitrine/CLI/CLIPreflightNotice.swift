import Foundation
import VitrineRendering

/// The CLI cannot ask, so it exports what was requested and warns on stderr. The note
/// names rows and rule kinds, never the matched text, and does not change the exit status.
enum CLIPreflightNotice {
    static func message(for config: SnapshotConfig, source: String? = nil) -> String? {
        let report = ExportPreflight(config, payload: .text)
        guard !report.isClean else { return nil }
        // Name the rows by the numbers the gutter shows, which `--lines` starts past 1.
        let offset = config.firstLineNumber - 1
        let places = report.findings.map { finding in
            let place: String
            switch finding.location {
            case .lines(let range) where range.count == 1:
                place = "line \(range.lowerBound + offset)"
            case .lines(let range):
                place = "lines \(range.lowerBound + offset)-\(range.upperBound + offset)"
            case .terminalTranscript: place = "terminal transcript"
            case .label: place = "header or annotation text"
            }
            return "\(place) (\(finding.kind))"
        }
        let subject = source.map { "\($0): " } ?? ""
        let hint = report.redactableLines.isEmpty ? "" : "; --redact-secrets hides these rows"
        return "vitrine: warning: \(subject)possible secrets at "
            + "\(places.joined(separator: ", ")); output unchanged\(hint)\n"
    }

    static func report(_ config: SnapshotConfig, source: String? = nil) {
        guard let message = message(for: config, source: source) else { return }
        FileHandle.standardError.write(Data(message.utf8))
    }
}
