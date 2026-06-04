import AppKit

/// Quick mode: read the clipboard, detect the content, render with the saved
/// settings, store it in Recents, and put the result back on the clipboard — no
/// UI (CS-009). The clipboard source is injectable so the logic is unit-testable.
enum QuickCapture {
    /// What happened during a quick capture, for user feedback (CS-016).
    enum Outcome: Equatable {
        case copied  // rendered and copied to the clipboard
        case rendered  // rendered but auto-copy is off
        case url(String)  // a URL was detected and URL→screenshot is enabled (Phase B)
        case empty  // clipboard had no usable text
    }

    @discardableResult
    static func run(
        settings: AppSettings,
        recents: RecentsStore = .shared,
        clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    ) -> Outcome {
        guard let text = clipboard(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return .empty }

        // URL → screenshot is Phase B; only branch off when the user opted in.
        if settings.treatURLsAsScreenshot, LanguageDetector.isURL(text) {
            // TODO: Phase B — WKWebView snapshot of the URL.
            return .url(text)
        }

        var config = settings.config
        config.code = text
        config.language = LanguageDetector.detect(text)
        settings.noteLanguageUsed(config.language)

        let scale = CGFloat(settings.exportScale)
        let didCopy = settings.autoCopy && ExportManager.copyToPasteboard(config, scale: scale)
        if settings.alsoSaveToFile {
            ExportManager.saveToFile(config, scale: scale, format: settings.exportFormat)
        }

        recents.add(
            Capture(code: text, languageID: config.language.rawValue, themeID: config.theme.id))

        return didCopy ? .copied : .rendered
    }
}
