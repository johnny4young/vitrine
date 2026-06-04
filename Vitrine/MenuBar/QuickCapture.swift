import AppKit

/// Quick mode: read the clipboard, detect the content, render with the saved
/// settings, and put the result back on the clipboard — no UI (CS-009).
enum QuickCapture {
    /// What happened during a quick capture, for optional UI feedback.
    enum Outcome: Equatable {
        case copied
        case rendered  // rendered but auto-copy is off
        case url(String)  // a URL was detected (screenshot is Phase B)
        case empty  // clipboard had no usable text
    }

    @discardableResult
    static func run(settings: AppSettings) -> Outcome {
        guard let text = NSPasteboard.general.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .empty }

        // URL → screenshot is Phase B (WKWebView). For now, signal and bail.
        if LanguageDetector.isURL(text) {
            // TODO: Phase B — WKWebView snapshot of the URL.
            return .url(text)
        }

        var config = settings.config
        config.code = text
        config.language = LanguageDetector.detect(text)

        let scale = CGFloat(settings.exportScale)
        guard settings.autoCopy else { return .rendered }

        ExportManager.copyToPasteboard(config, scale: scale)
        return .copied
    }
}
