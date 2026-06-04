import AppKit
import OSLog

/// Quick mode: read the clipboard, detect the content, render with the saved
/// settings, store it in Recents, and put the result back on the clipboard — no
/// UI (CS-009). The clipboard source is injectable so the logic is unit-testable.
enum QuickCapture {
    /// What happened during a quick capture, for user feedback (CS-016).
    enum Outcome: Equatable {
        case copied  // rendered and copied to the clipboard
        case rendered  // rendered but auto-copy is off
        case url(String)  // a URL was detected and URL→screenshot is enabled (Product Phase 2)
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
        else {
            Log.capture.info("Quick capture: clipboard empty")
            return .empty
        }

        // URL → screenshot is Product Phase 2; only branch off when the user opted in.
        if settings.treatURLsAsScreenshot, LanguageDetector.isURL(text) {
            // TODO: CS-043 — WKWebView snapshot of the URL.
            // Never log the URL itself; record only that the branch was taken.
            Log.capture.info("Quick capture: URL detected (screenshot deferred)")
            return .url(text)
        }

        var config = settings.config
        config.code = text
        config.language = LanguageDetector.detect(text)
        settings.noteLanguageUsed(config.language)

        // Non-PII telemetry only: the detected language name and a length measure,
        // never the clipboard contents (CS-048).
        Log.capture.info(
            "Quick capture: detected \(config.language.rawValue, privacy: .public), \(text.count, privacy: .public) chars"
        )

        // Honor the active destination preset's framing (size/scale) so quick
        // capture produces the same image the editor would (CS-020).
        let scale = CGFloat(settings.effectiveExportScale)
        let fixedSize = settings.effectiveFixedSize
        let profile = settings.colorProfile
        let didCopy =
            settings.autoCopy
            && ExportManager.copyToPasteboard(
                config, scale: scale, fixedSize: fixedSize, profile: profile)
        if settings.alsoSaveToFile {
            ExportManager.saveToFile(
                config, scale: scale, format: settings.exportFormat, fixedSize: fixedSize,
                profile: profile)
        }

        recents.add(
            Capture(code: text, languageID: config.language.rawValue, themeID: config.theme.id))

        Log.capture.notice(
            "Quick capture complete (\(didCopy ? "copied" : "rendered", privacy: .public))")
        return didCopy ? .copied : .rendered
    }
}
