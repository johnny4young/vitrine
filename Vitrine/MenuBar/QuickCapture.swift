import AppKit
import OSLog
import UniformTypeIdentifiers
import VitrineDomain
import VitrineRendering

/// Quick mode: read the clipboard, detect the content, render with the saved
/// settings, store it in Recents, and put the result back on the clipboard — no
/// UI. The clipboard source is injectable so the logic is unit-testable.
enum QuickCapture {
    /// A fully resolved export request. Keeping the presentation config and output
    /// geometry together prevents quick actions from applying a preset's colors and
    /// padding while accidentally rendering at the user's unrelated default size.
    struct RenderPlan {
        var config: SnapshotConfig
        let scale: CGFloat
        let fixedSize: CGSize?
    }

    /// What happened during a quick capture, for user feedback.
    enum Outcome: Equatable {
        case copied  // rendered and copied to the clipboard
        case rendered  // rendered but auto-copy is off
        case renderFailed(RenderBudgetError)  // rejected or failed before producing an image
        case url(String)  // a URL was detected and URL capture is enabled by the user
        case empty  // clipboard had no usable text
        // Several Markdown code blocks were detected; the combined source is loaded
        // into the editor for the user to choose how to frame it. The
        // associated count is the number of blocks, for the feedback message.
        case deferredToEditor(blocks: Int)
    }

    /// The full result of a quick capture: the outcome plus what actually happened
    /// to the produced image, so the feedback layer can name the destination
    /// precisely — copied, saved, both, or neither.
    struct Result: Equatable {
        var outcome: Outcome
        var copiedToClipboard: Bool
        var savedToFile: Bool
        /// The document to open when the capture defers to the editor. It carries the
        /// one-off destination framing without writing it into the app-wide default.
        var editorDocument: SnapshotConfig? = nil

        /// A result that produced no image (empty clipboard, URL, deferred).
        static func nonProducing(_ outcome: Outcome) -> Result {
            Result(outcome: outcome, copiedToClipboard: false, savedToFile: false)
        }
    }

    /// Internal export result that keeps a pre-allocation render rejection separate
    /// from ordinary pasteboard or save-panel failures. The public `Outcome` exposes
    /// only the render category needed for actionable feedback.
    private enum ExportAttempt {
        case completed(didCopy: Bool, didSave: Bool)
        case renderFailed(RenderBudgetError)
    }

    /// Runs a quick capture and reports the full `Result` (outcome + copied/saved
    /// state) for precise feedback.
    static func capture(
        settings: AppSettings,
        recents: RecentsStore,
        destinationPreset: ExportPreset? = nil,
        clipboard: () -> String? = { NSPasteboard.general.string(forType: .string) },
        historyConsent: RecentsStore.ConsentResolver? = nil,
        urlCaptureEnabled: Bool = NetworkCapability.isURLCaptureEnabled
    ) -> Result {
        guard let text = clipboard(),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            Log.capture.info("Quick capture: clipboard empty")
            return .nonProducing(.empty)
        }

        // A URL branches off only when the user opted in and this build can capture
        // it; otherwise it renders as text. `perform()` opens Web Snapshot for `.url`.
        if settings.treatURLsAsScreenshot, urlCaptureEnabled, classifyURL(text) != nil {
            // Never log the URL itself; record only that the branch was taken.
            Log.capture.info("Quick capture: URL detected")
            return .nonProducing(.url(text))
        }

        // Understand common clipboard formats — Markdown fences and file paths —
        // before falling back to raw content scoring. A single fenced
        // block is unwrapped to its inner code; a lone file path names its
        // language by extension; plain text is returned unchanged.
        let interpreted = LanguageDetector.interpret(text)

        var config = settings.config.replacingContent(
            with: interpreted.code, language: interpreted.language)
        var plan = renderPlan(
            for: config, settings: settings, destinationPreset: destinationPreset)
        config = plan.config

        // Several fenced blocks are ambiguous to render inline: hand the combined
        // source to the editor and defer the choice to the user, recording nothing,
        // copying nothing, and leaving the app-wide default untouched.
        if interpreted.hasMultipleBlocks {
            settings.noteLanguageUsed(config.language)
            Log.capture.info(
                "Quick capture: \(interpreted.blockCount, privacy: .public) code blocks → editor"
            )
            var result = Result.nonProducing(.deferredToEditor(blocks: interpreted.blockCount))
            result.editorDocument = config
            return result
        }

        settings.noteLanguageUsed(config.language)

        // Non-PII telemetry only: the detected language name and a length measure,
        // never the clipboard contents.
        Log.capture.info(
            "Quick capture: detected \(config.language.rawValue, privacy: .public), \(config.code.count, privacy: .public) chars"
        )

        // Apply the PRO brand-kit watermark on the export path only: the multi-block
        // branch above returns first, so the editor document is never watermarked.
        config.watermark = settings.exportWatermark

        // Honor the active destination preset's framing (size/scale) so quick
        // capture produces the same image the editor would. Render once and
        // reuse the raster for both the copy and the save.
        plan.config = config
        let attempt = copyAndSave(plan, settings: settings)
        let didCopy: Bool
        let didSave: Bool
        switch attempt {
        case .completed(let copied, let saved):
            didCopy = copied
            didSave = saved
        case .renderFailed(let error):
            Log.capture.error("Quick capture stopped: render failed safely")
            return .nonProducing(.renderFailed(error))
        }

        recents.record(config, consent: historyConsent)

        Log.capture.notice(
            "Quick capture complete (\(didCopy ? "copied" : "rendered", privacy: .public))")
        return Result(
            outcome: didCopy ? .copied : .rendered,
            copiedToClipboard: didCopy,
            savedToFile: didSave)
    }

    /// Renders `config` once and applies the requested clipboard copy and file save from
    /// that single raster, so the hotkey path no longer renders the identical config
    /// twice (once to copy, once to save). Returns whether each side effect ran.
    ///
    /// The rich-clipboard/plain-text copy reuses the same raster and only adds RTF/HTML
    /// derived from the code; a PDF save is a vector document, so it renders its own page
    /// through the `config`-based save rather than the shared raster.
    /// Whether `copyAndSave` must produce the shared raster: the clipboard copy
    /// and bitmap file saves consume it, while a PDF save renders its own vector
    /// page from the config. Pure and exposed so the regression test can pin the
    /// PDF-only case, where a raster budget preflight must never fail a save
    /// that does not need the bitmap.
    nonisolated static func rasterIsRequired(
        autoCopy: Bool, savesToFile: Bool, format: ExportFormat
    ) -> Bool {
        autoCopy || (savesToFile && format != .pdf)
    }

    private static func copyAndSave(
        _ plan: RenderPlan, settings: AppSettings, pasteboard: NSPasteboard = .general
    ) -> ExportAttempt {
        let profile = settings.export.colorProfile
        // The shared raster feeds the clipboard copy and bitmap file saves; a PDF
        // save renders its own vector page from `config`. Skip rasterization when
        // no destination consumes the bitmap, so an over-budget natural layout
        // cannot fail a PDF-only save that never needed it — the checked PDF
        // encoder decides that outcome itself.
        let needsRaster = rasterIsRequired(
            autoCopy: settings.outputBehavior.autoCopy,
            savesToFile: settings.outputBehavior.alsoSaveToFile,
            format: settings.export.format)
        let cgImage: CGImage?
        if needsRaster {
            do {
                cgImage = try ExportManager.renderCGImageChecked(
                    plan.config, scale: plan.scale, fixedSize: plan.fixedSize, profile: profile)
            } catch let error {
                return .renderFailed(error)
            }
        } else {
            cgImage = nil
        }

        var didCopy = false
        var deferredRenderFailure: RenderBudgetError?
        // `autoCopy` implies `needsRaster`, so the binding always succeeds here;
        // it simply keeps the optional handling explicit.
        if settings.outputBehavior.autoCopy, let cgImage {
            if settings.export.richClipboard || settings.export.textSidecar {
                switch RichPasteboard.copyOutcome(
                    cgImage: cgImage, config: plan.config,
                    includeRichText: settings.export.richClipboard,
                    includePlainText: settings.export.textSidecar,
                    concealed: settings.outputBehavior.concealClipboard, to: pasteboard)
                {
                case .copied:
                    didCopy = true
                case .failed:
                    didCopy = false
                case .renderFailed(let error):
                    deferredRenderFailure = error
                }
            } else {
                switch ExportManager.copyPNGToPasteboardOutcome(
                    cgImage, concealed: settings.outputBehavior.concealClipboard, to: pasteboard)
                {
                case .copied:
                    didCopy = true
                case .failed:
                    didCopy = false
                case .renderFailed(let error):
                    deferredRenderFailure = error
                }
            }
        }

        var didSave = false
        if settings.outputBehavior.alsoSaveToFile {
            if settings.export.format == .pdf {
                let outcome = ExportManager.saveToFile(
                    plan.config, scale: plan.scale, format: .pdf,
                    fixedSize: plan.fixedSize, profile: profile)
                didSave = outcome == .saved
                if case .renderFailed(let error) = outcome {
                    deferredRenderFailure = deferredRenderFailure ?? error
                }
            } else if let cgImage {
                let outcome = ExportManager.saveToFile(
                    cgImage: cgImage, format: settings.export.format,
                    suggestedName: SuggestedFilename.basename(for: plan.config))
                didSave = outcome == .saved
                if case .renderFailed(let error) = outcome {
                    deferredRenderFailure = deferredRenderFailure ?? error
                }
            }
        }
        if !didCopy, !didSave, let deferredRenderFailure {
            return .renderFailed(deferredRenderFailure)
        }
        return .completed(didCopy: didCopy, didSave: didSave)
    }

    /// Resolves a one-off destination preset without changing the user's saved default.
    /// The preset owns both presentation guidance and output geometry; without one, the
    /// regular quick-capture settings remain authoritative.
    static func renderPlan(
        for config: SnapshotConfig,
        settings: AppSettings,
        destinationPreset: ExportPreset?
    ) -> RenderPlan {
        var resolved = config
        destinationPreset?.apply(to: &resolved)
        return RenderPlan(
            config: resolved,
            scale: CGFloat(destinationPreset?.scale ?? settings.effectiveExportScale),
            fixedSize: destinationPreset?.sizing.fixedSize ?? settings.effectiveFixedSize)
    }

    /// Imports an image from the clipboard into the foreground store, or `nil` when the
    /// clipboard carries no image (the common text case). Prefers raw PNG/TIFF bytes so the
    /// original is stored without re-encoding. The pasteboard and store are injectable so
    /// the path is unit-testable without the real container.
    static func clipboardForegroundImage(
        pasteboard: NSPasteboard = .general,
        store: BackgroundImageStore = .foregroundContainer
    ) -> ImageReference? {
        // Prefer lossless PNG/TIFF, then fall back to any other image representation, so a
        // copied screenshot is stored at full fidelity even when AppKit also offers a JPEG
        // in `pasteboard.types` (whose order is not guaranteed).
        let available = pasteboard.types ?? []
        let preferred: [NSPasteboard.PasteboardType] = [.png, .tiff]
        let ordered = preferred + available.filter { !preferred.contains($0) }
        for pasteboardType in ordered {
            guard
                let type = UTType(pasteboardType.rawValue),
                type.conforms(to: .image),
                let data = pasteboard.data(forType: pasteboardType)
            else { continue }
            if let reference = try? store.importImage(
                data: data, preferredExtension: type.preferredFilenameExtension ?? "")
            {
                return reference
            }
        }
        return nil
    }

    // MARK: - Input classification

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
    /// reading and the URL branch.
    ///
    /// Uses the same output settings as a normal capture; pass `recents: nil` to
    /// keep the render out of history (the Welcome sample does).
    @discardableResult
    static func renderText(
        _ text: String,
        language: Language = .plaintext,
        settings: AppSettings,
        recents: RecentsStore?,
        pasteboard: NSPasteboard = .general,
        historyConsent: RecentsStore.ConsentResolver? = nil
    ) -> Result {
        var config = settings.config.replacingContent(with: text, language: language)
        if recents != nil { settings.noteLanguageUsed(language) }
        // Apply the PRO brand-kit watermark to the rendered image.
        config.watermark = settings.exportWatermark

        // Render once and reuse the raster for both the copy and the save.
        var plan = renderPlan(for: config, settings: settings, destinationPreset: nil)
        plan.config = config
        let attempt = copyAndSave(plan, settings: settings, pasteboard: pasteboard)
        let didCopy: Bool
        let didSave: Bool
        switch attempt {
        case .completed(let copied, let saved):
            didCopy = copied
            didSave = saved
        case .renderFailed(let error):
            Log.capture.error("Text capture stopped: render failed safely")
            return .nonProducing(.renderFailed(error))
        }

        recents?.record(config, consent: historyConsent)
        Log.capture.notice(
            "Rendered text capture (\(didCopy ? "copied" : "rendered", privacy: .public))")
        return Result(
            outcome: didCopy ? .copied : .rendered,
            copiedToClipboard: didCopy,
            savedToFile: didSave)
    }

    /// Runs a quick capture and applies its user-facing side effects: opens the
    /// editor when several code blocks were deferred to it, then shows
    /// tasteful feedback — an in-app HUD for routine success, with inline recovery
    /// actions for dead ends. The menu and the global hotkey both
    /// call this so behavior is consistent across entry points.
    static func perform(
        environment: AppEnvironment,
        feedback: CaptureFeedbackPresenter,
        destinationPreset: ExportPreset? = nil
    ) {
        let settings = environment.appSettings
        let recents = environment.recents
        // A copied image becomes a beautified capture (the "beautify any image" feature):
        // open the editor with it framed on the saved background, where the user picks a
        // frame and exports. Checked before the text path, since a screenshot carries image
        // data, not a string.
        if let reference = clipboardForegroundImage() {
            var config = settings.config
            config.clearContentMarks()
            config.foregroundImage = reference
            let plan = renderPlan(
                for: config, settings: settings, destinationPreset: destinationPreset)
            feedback.routing.loadIntoPrimaryEditor(plan.config)
            Log.capture.info("Quick capture: clipboard image → editor")
            return
        }

        let result = capture(
            settings: settings,
            recents: recents,
            destinationPreset: destinationPreset,
            historyConsent: HistoryConsentPrompt.resolve)
        switch result.outcome {
        case .deferredToEditor:
            if let document = result.editorDocument {
                feedback.routing.loadIntoPrimaryEditor(document)
            }
            feedback.present(result, environment: environment)
        case .url(let text):
            // Web Snapshot owns the privacy disclosure and the local capture.
            feedback.routing.showWebSnapshot(prefillURL: text)
        default:
            feedback.present(result, environment: environment)
        }
    }
}
