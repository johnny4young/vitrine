import AppKit
import VitrineRendering

/// Asks what to do when an export would carry flagged text. It names rows and kinds but
/// never quotes the match, so the dialog cannot itself show a secret on a shared screen.
enum ExportPreflightPrompt {
    enum Choice: Equatable {
        case cancel, redact, proceed
    }

    typealias Resolver = (ExportPreflight, ExportPreflight.Action) -> Choice

    private static let maximumRows = 6

    static func resolve(
        _ report: ExportPreflight, action: ExportPreflight.Action
    ) -> Choice {
        let alert = makeAlert(report, action: action)
        // A global hotkey runs this with another app frontmost, so open above it. The caller
        // returns focus once every prompt and save panel of the capture is done.
        AppActivation.bringForward()
        alert.window.level = .modalPanel
        let response = alert.runModal()
        return choice(for: response, canRedact: !report.redactableLines.isEmpty)
    }

    static func makeAlert(_ report: ExportPreflight, action: ExportPreflight.Action) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "This capture may contain secrets")
        alert.informativeText =
            rows(for: report).joined(separator: "\n") + "\n\n"
            + String(localized: "Detection is not exhaustive.")
        let cancel = String(localized: "Cancel")
        let anyway = anywayTitle(for: action)
        if report.redactableLines.isEmpty {
            // Nothing can be redacted, so the safe choice stays first and no positive
            // decision is bound to Return.
            let cancelButton = alert.addButton(withTitle: cancel)
            cancelButton.setAccessibilityIdentifier("export-preflight-cancel")
            cancelButton.keyEquivalent = "\u{1b}"
            let anywayButton = alert.addButton(withTitle: anyway)
            anywayButton.setAccessibilityIdentifier("export-preflight-anyway")
            anywayButton.keyEquivalent = ""
        } else {
            let redact = alert.addButton(
                withTitle: redactTitle(count: report.redactableLines.count, action: action))
            redact.setAccessibilityIdentifier("export-preflight-redact")
            let anywayButton = alert.addButton(withTitle: anyway)
            anywayButton.setAccessibilityIdentifier("export-preflight-anyway")
            anywayButton.keyEquivalent = ""
            let cancelButton = alert.addButton(withTitle: cancel)
            cancelButton.setAccessibilityIdentifier("export-preflight-cancel")
            cancelButton.keyEquivalent = "\u{1b}"
        }
        return alert
    }

    static func choice(for response: NSApplication.ModalResponse, canRedact: Bool) -> Choice {
        switch (response, canRedact) {
        case (.alertFirstButtonReturn, true): .redact
        case (.alertSecondButtonReturn, _): .proceed
        default: .cancel
        }
    }

    static func rows(for report: ExportPreflight) -> [String] {
        let rows = report.findings.map(row)
        guard rows.count > maximumRows else { return rows }
        let remaining = rows.count - maximumRows
        return rows.prefix(maximumRows) + [String(localized: "And \(remaining) more")]
    }

    private static func row(_ finding: ExportPreflight.Finding) -> String {
        let name = kindName(finding.kind)
        switch finding.location {
        case .lines(let range) where range.count == 1:
            return String(localized: "Line \(range.lowerBound): \(name)")
        case .lines(let range):
            return String(localized: "Lines \(range.lowerBound)–\(range.upperBound): \(name)")
        case .terminalTranscript:
            return String(localized: "Full terminal transcript: \(name)")
        case .label:
            return String(localized: "Header or annotation text, can't be redacted: \(name)")
        }
    }

    private static func kindName(_ kind: String) -> String {
        switch kind {
        case "aws-access-key": String(localized: "AWS access key")
        case "github-token": String(localized: "GitHub token")
        case "slack-token": String(localized: "Slack token")
        case "google-api-key": String(localized: "Google API key")
        case "stripe-key": String(localized: "Stripe key")
        case "openai-key": String(localized: "OpenAI key")
        case "jwt": String(localized: "JSON Web Token")
        case "private-key": String(localized: "Private key")
        case "bearer-token": String(localized: "Bearer token")
        case "url-credentials": String(localized: "Password in a URL")
        default: String(localized: "Possible secret")
        }
    }

    private static func redactTitle(count: Int, action: ExportPreflight.Action) -> String {
        switch action {
        case .copy: String(localized: "Redact \(count) and copy")
        case .save: String(localized: "Redact \(count) and save")
        case .copyAndSave: String(localized: "Redact \(count), copy and save")
        case .share: String(localized: "Redact \(count) and share")
        case .export: String(localized: "Redact \(count) and export")
        }
    }

    private static func anywayTitle(for action: ExportPreflight.Action) -> String {
        switch action {
        case .copy: String(localized: "Copy anyway")
        case .save: String(localized: "Save anyway")
        case .copyAndSave: String(localized: "Copy and save anyway")
        case .share: String(localized: "Share anyway")
        case .export: String(localized: "Export anyway")
        }
    }
}
