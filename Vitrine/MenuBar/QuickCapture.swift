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
        // Several Markdown code blocks were detected; the combined source is loaded
        // into the editor for the user to choose how to frame it (CS-027). The
        // associated count is the number of blocks, for the feedback message.
        case deferredToEditor(blocks: Int)
    }

    /// The full result of a quick capture: the outcome plus what actually happened
    /// to the produced image, so the feedback layer can name the destination
    /// precisely — copied, saved, both, or neither (CS-038). `run` returns only the
    /// `outcome` for its existing callers and tests; `capture` returns this.
    struct Result: Equatable {
        var outcome: Outcome
        var copiedToClipboard: Bool
        var savedToFile: Bool

        /// A result that produced no image (empty clipboard, URL, deferred).
        static func nonProducing(_ outcome: Outcome) -> Result {
            Result(outcome: outcome, copiedToClipboard: false, savedToFile: false)
        }
    }

    @discardableResult
    static func run(
        settings: AppSettings,
        recents: RecentsStore = .shared,
        clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    ) -> Outcome {
        capture(settings: settings, recents: recents, clipboard: clipboard).outcome
    }

    /// Runs a quick capture and reports the full `Result` (outcome + copied/saved
    /// state) for precise feedback (CS-038). `run` is the thin wrapper that keeps
    /// returning just the outcome.
    static func capture(
        settings: AppSettings,
        recents: RecentsStore = .shared,
        clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) }
    ) -> Result {
        guard let text = clipboard(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            Log.capture.info("Quick capture: clipboard empty")
            return .nonProducing(.empty)
        }

        // URL → screenshot is Product Phase 2; only branch off when the user opted in.
        if settings.treatURLsAsScreenshot, LanguageDetector.isURL(text) {
            // TODO: CS-043 — WKWebView snapshot of the URL.
            // Never log the URL itself; record only that the branch was taken.
            Log.capture.info("Quick capture: URL detected (screenshot deferred)")
            return .nonProducing(.url(text))
        }

        // Understand common clipboard formats — Markdown fences and file paths —
        // before falling back to raw content scoring (CS-027). A single fenced
        // block is unwrapped to its inner code; a lone file path names its
        // language by extension; plain text is returned unchanged.
        let interpreted = LanguageDetector.interpret(text)

        var config = settings.config
        config.code = interpreted.code
        config.language = interpreted.language

        // Several fenced blocks are ambiguous to render inline: load the combined
        // source into the editor and defer the choice to the user, recording
        // nothing and copying nothing (CS-027). The call site opens the editor.
        if interpreted.hasMultipleBlocks {
            settings.config = config
            settings.noteLanguageUsed(config.language)
            Log.capture.info(
                "Quick capture: \(interpreted.blockCount, privacy: .public) code blocks → editor"
            )
            return .nonProducing(.deferredToEditor(blocks: interpreted.blockCount))
        }

        settings.noteLanguageUsed(config.language)

        // Non-PII telemetry only: the detected language name and a length measure,
        // never the clipboard contents (CS-048).
        Log.capture.info(
            "Quick capture: detected \(config.language.rawValue, privacy: .public), \(config.code.count, privacy: .public) chars"
        )

        // Honor the active destination preset's framing (size/scale) so quick
        // capture produces the same image the editor would (CS-020).
        let scale = CGFloat(settings.effectiveExportScale)
        let fixedSize = settings.effectiveFixedSize
        let profile = settings.colorProfile
        let didCopy =
            settings.autoCopy
            && ExportManager.copyToPasteboard(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                richText: settings.richClipboard)
        let didSave =
            settings.alsoSaveToFile
            && ExportManager.saveToFile(
                config, scale: scale, format: settings.exportFormat, fixedSize: fixedSize,
                profile: profile) == .saved

        recents.add(
            Capture(
                code: config.code, languageID: config.language.rawValue,
                themeID: config.theme.id))

        Log.capture.notice(
            "Quick capture complete (\(didCopy ? "copied" : "rendered", privacy: .public))")
        return Result(
            outcome: didCopy ? .copied : .rendered,
            copiedToClipboard: didCopy,
            savedToFile: didSave)
    }

    /// Renders an explicit string as a plain-text capture, bypassing clipboard
    /// reading and the URL branch (CS-038).
    ///
    /// This backs the "Render as Text" recovery offered when a clipboard URL is
    /// detected but URL → screenshot capture has not shipped yet (Product Phase 2):
    /// rather than leaving the user stuck, the URL text itself is framed as a
    /// plain-text snippet using the same output settings as a normal capture.
    @discardableResult
    static func renderText(
        _ text: String,
        language: Language = .plaintext,
        settings: AppSettings,
        recents: RecentsStore = .shared
    ) -> Result {
        var config = settings.config
        config.code = text
        config.language = language
        settings.noteLanguageUsed(language)

        let scale = CGFloat(settings.effectiveExportScale)
        let fixedSize = settings.effectiveFixedSize
        let profile = settings.colorProfile
        let didCopy =
            settings.autoCopy
            && ExportManager.copyToPasteboard(
                config, scale: scale, fixedSize: fixedSize, profile: profile,
                richText: settings.richClipboard)
        let didSave =
            settings.alsoSaveToFile
            && ExportManager.saveToFile(
                config, scale: scale, format: settings.exportFormat, fixedSize: fixedSize,
                profile: profile) == .saved

        recents.add(
            Capture(
                code: config.code, languageID: config.language.rawValue,
                themeID: config.theme.id))
        Log.capture.notice(
            "Rendered text capture (\(didCopy ? "copied" : "rendered", privacy: .public))")
        return Result(
            outcome: didCopy ? .copied : .rendered,
            copiedToClipboard: didCopy,
            savedToFile: didSave)
    }

    /// Runs a quick capture and applies its user-facing side effects: opens the
    /// editor when several code blocks were deferred to it (CS-027), then shows
    /// tasteful feedback — an in-app HUD for routine success, with inline recovery
    /// actions for dead ends (CS-016, CS-038). The menu and the global hotkey both
    /// call this so behavior is consistent across entry points.
    static func perform(settings: AppSettings = .shared) {
        let result = capture(settings: settings)
        if case .deferredToEditor = result.outcome {
            EditorWindowController.shared.show()
        }
        CaptureFeedbackPresenter.shared.present(result, settings: settings)
    }
}
