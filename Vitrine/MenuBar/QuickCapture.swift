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
        case url(String)  // a URL was detected and URL capture is enabled by the user
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

        // URL → screenshot capture only branches off when the user opted in.
        // The classified URL becomes a `.url` outcome: the app's `perform()` opens the
        // Web Snapshot window (which owns the privacy disclosure and the async render),
        // while a headless caller can offer the "Render as Text" recovery (CS-038).
        // `capture()` stays synchronous and UI-free — it only classifies and reports
        // the outcome, so it carries no dependency on the windowed render path.
        if settings.treatURLsAsScreenshot, classifyURL(text) != nil {
            // Never log the URL itself; record only that the branch was taken.
            Log.capture.info("Quick capture: URL detected")
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

        // Apply the PRO brand-kit watermark to the rendered image (CS-092). Set here,
        // on the export path only: the multi-block "load into editor" branch above
        // returns first, so the stored `settings.config` is never watermarked.
        config.watermark = BrandKitStore.shared.resolvedWatermark(
            isPro: Entitlements.shared.isPro)

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

    // MARK: - Input classification (CS-040)

    /// Classifies raw clipboard text into a typed `CaptureInput` for the renderer
    /// abstraction, *without rendering* — the seam that keeps the Phase 1 code path
    /// free of Phase 2's URL assumptions (CS-040).
    ///
    /// When `treatURLsAsScreenshot` is on and the text is a single http(s) URL, the
    /// input is `.url`; otherwise the text is interpreted (Markdown fences, file
    /// paths, content scoring) and returned as `.code` carrying the detected
    /// language as its hint. HTML is not produced from clipboard text here — pasted
    /// HTML arrives through a dedicated Phase 2 entry point, not by sniffing the
    /// code path — so plain HTML source still classifies as `.code` (highlighted)
    /// exactly as before.
    static func classify(_ text: String, treatURLsAsScreenshot: Bool) -> CaptureInput {
        if treatURLsAsScreenshot, let url = classifyURL(text) {
            return url
        }
        let interpreted = LanguageDetector.interpret(text)
        return .code(interpreted.code, languageHint: interpreted.language)
    }

    /// Returns a `.url` input when `text` is a single http(s) URL that `URL` can
    /// parse, or `nil` otherwise. This pairs `LanguageDetector.isURL` (the textual
    /// gate, which the rest of the app already trusts) with an actual `URL` value
    /// for the renderer, so a string that passes the gate but cannot form a `URL`
    /// falls through to the code path rather than producing a broken URL input.
    static func classifyURL(_ text: String) -> CaptureInput? {
        guard LanguageDetector.isURL(text) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        return .url(url)
    }

    /// Renders an explicit string as a plain-text capture, bypassing clipboard
    /// reading and the URL branch (CS-038).
    ///
    /// This backs the "Render as Text" recovery offered when a clipboard URL is
    /// detected but the user chooses not to open Web Snapshot: the URL text itself
    /// is framed as a plain-text snippet using the same output settings as a normal
    /// capture.
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
        // Apply the PRO brand-kit watermark to the rendered image (CS-092).
        config.watermark = BrandKitStore.shared.resolvedWatermark(
            isPro: Entitlements.shared.isPro)

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
        switch result.outcome {
        case .deferredToEditor:
            // `capture` has already written the combined multi-block source into
            // `settings.config`; load that into the primary editor window so the user
            // sees it even if the editor was already open (CS-027 + CS-053: a plain
            // `show()` no longer clobbers an open window's per-window document).
            EditorWindowController.shared.loadIntoPrimary(settings.config)
            CaptureFeedbackPresenter.shared.present(result, settings: settings)
        case .url(let text):
            // A clipboard URL opens the Web Snapshot window preloaded with it — where
            // the privacy disclosure and the local capture live (CS-043) — rather than
            // the old deferred dead-end. `WebSnapshotPresenter` keeps this free of any
            // WebKit dependency, so the menu-bar path stays CLI-safe.
            WebSnapshotPresenter.show(prefillURL: text)
        default:
            CaptureFeedbackPresenter.shared.present(result, settings: settings)
        }
    }
}
