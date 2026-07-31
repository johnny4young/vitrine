import AppKit

/// Performs and validates the editor/document commands (Copy / Save / Share
/// Image) so they exist as real menu commands with keyboard shortcuts, not just
/// toolbar buttons. These mirror the editor toolbar exactly: both reach
/// the active editor settings and `ExportManager`, so the menu command and the
/// toolbar button always produce the same image.
///
/// One instance retained by the main-menu owner is the explicit target of the
/// editor menu items. Targeting it directly (rather than the responder chain)
/// keeps enablement deterministic and unit-testable: a command is enabled only
/// when an editor window is key — and, for the render commands, only when that
/// window holds code — which `canPerform(_:)` decides.
///
/// ## Multi-window
///
/// With more than one editor open, a menu command must act on whichever editor is
/// *key*, not on a fixed instance. The responder therefore resolves the key window's
/// own `EditorSession` at action time (``activeSettings``) and operates on its
/// per-window config, falling back to the injected `settings` when no editor session
/// is resolvable (the unit-test host, where no real window is key). "Make Default"
/// promotes that key window's style to the app-wide default.
final class EditorCommandResponder: NSObject, NSMenuItemValidation {
    let settings: AppSettings

    /// Small snippets format synchronously so the menu command feels instant. Larger
    /// snippets do the pure string work off the main actor and only return to AppKit
    /// for the final text replacement; beyond this cap, formatting is refused instead
    /// of risking an unresponsive editor.
    private static let asyncFormatThresholdBytes = 64 * 1024
    private static let maxInteractiveFormatBytes = 1 * 1024 * 1024

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    /// The settings the command should act on: the key editor window's own session,
    /// or the injected instance when none is resolvable (no editor key / test host).
    private var activeSettings: AppSettings {
        EditorWindowController.shared.keyWindowSession?.settings ?? settings
    }

    /// Whether `command` can run right now. Editor-scoped commands require an editor
    /// window to be key (so a Save/Share/Make Default from the menu acts on the visible
    /// editor); render commands additionally require visible content to render.
    func canPerform(_ command: VitrineCommand) -> Bool {
        Self.canPerform(command, isEditorKey: isEditorKey, config: activeSettings.config)
    }

    /// Pure command-gating core, separated so unit tests can cover content states without
    /// constructing real AppKit editor windows.
    static func canPerform(
        _ command: VitrineCommand, isEditorKey: Bool, config: SnapshotConfig
    ) -> Bool {
        guard command.isEditorScoped else { return true }
        guard isEditorKey else { return false }
        if command.requiresRenderableContent { return config.hasRenderableContent }
        if command.requiresCode { return !config.code.isEmpty }
        return true
    }

    /// True when the key window is an editor, or when no window is key and the main
    /// window is an editor. A non-editor key window deliberately keeps editor commands
    /// disabled; `EditorWindowController` tags every editor window with an
    /// `editor-window`-prefixed identifier, of which the primary is exactly
    /// `editor-window`.
    private var isEditorKey: Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        return window.accessibilityIdentifier().hasPrefix("editor-window")
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyRenderedImage(_:)): canPerform(.copyImage)
        case #selector(saveRenderedImage(_:)): canPerform(.saveImage)
        case #selector(shareRenderedImage(_:)): canPerform(.shareImage)
        case #selector(makeWindowDefault(_:)): canPerform(.makeDefault)
        case #selector(formatCode(_:)): canPerform(.formatCode)
        case #selector(selectAnnotationTool(_:)): isEditorKey
        default: true
        }
    }

    @objc func copyRenderedImage(_ sender: Any?) {
        guard canPerform(.copyImage) else { return }
        let settings = activeSettings
        // Surface the outcome so a render/encode failure from the menu isn't silent,
        // mirroring the quick-capture HUD path.
        let copied = ExportManager.copyToPasteboard(
            settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile,
            richText: settings.export.richClipboard, plainText: settings.export.textSidecar)
        CaptureHUDController.shared.present(
            copied
                ? Notifier.confirmation(String(localized: "Image copied to clipboard"))
                : Notifier.failure(String(localized: "Couldn't copy the image")))
    }

    @objc func saveRenderedImage(_ sender: Any?) {
        guard canPerform(.saveImage) else { return }
        let settings = activeSettings
        switch ExportManager.saveToFile(
            settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
            format: settings.export.format, fixedSize: settings.effectiveFixedSize,
            profile: settings.export.colorProfile)
        {
        case .saved:
            CaptureHUDController.shared.present(
                Notifier.confirmation(String(localized: "Image saved")))
        case .failed:
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Couldn't save the image")))
        case .cancelled:
            break  // the user dismissed the save panel — no feedback needed
        }
    }

    @objc func shareRenderedImage(_ sender: Any?) {
        let settings = activeSettings
        guard canPerform(.shareImage),
            let image = ExportManager.renderNSImage(
                settings.exportConfig, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize, profile: settings.export.colorProfile),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
    }

    /// Promotes the key editor window's current style to the app-wide default.
    /// A no-op when no editor window is key, so it cannot adopt a phantom configuration.
    @objc func makeWindowDefault(_ sender: Any?) {
        guard canPerform(.makeDefault),
            let session = EditorWindowController.shared.keyWindowSession
        else { return }
        session.makeDefault()
    }

    /// Routes a tool command to the key editor window. The window is the
    /// notification object so other open editors ignore the selection.
    @objc func selectAnnotationTool(_ sender: Any?) {
        guard isEditorKey,
            let item = sender as? NSMenuItem,
            let rawValue = item.representedObject as? String,
            AnnotationTool(rawValue: rawValue) != nil,
            let window = NSApp.keyWindow ?? NSApp.mainWindow
        else { return }
        NotificationCenter.default.post(
            name: .vitrineSelectAnnotationTool,
            object: window,
            userInfo: ["tool": rawValue])
    }

    /// Tidies the key editor's code in place: JSON is pretty-printed, brace and
    /// JSX/tag languages are re-indented by structure, indentation-significant languages
    /// are dedented, and diff/plain text is left alone (see `CodeFormatter.tidy`). The
    /// edit goes through the text view's native edit cycle
    /// (`shouldChangeText` / `replaceCharacters` / `didChangeText`) instead of mutating the
    /// model directly, so it lands on the editor's own undo stack — ⌘Z reverts a surprising
    /// reformat, exactly like undoing a paste — and `textDidChange` writes the result back
    /// into `config.code`. A no-op (already tidy) changes nothing and registers no undo.
    @objc func formatCode(_ sender: Any?) {
        guard canPerform(.formatCode),
            let textView = Self.editorTextView(in: NSApp.keyWindow ?? NSApp.mainWindow)
        else { return }
        let original = textView.string
        let byteCount = original.utf8.count
        guard byteCount <= Self.maxInteractiveFormatBytes else {
            CaptureHUDController.shared.present(
                Notifier.failure(String(localized: "Code is too large to format interactively")))
            return
        }

        let language = activeSettings.config.language
        if byteCount > Self.asyncFormatThresholdBytes {
            Task { [weak textView] in
                let tidied = await Task.detached(priority: .userInitiated) {
                    CodeFormatter.tidy(original, language: language)
                }.value
                guard let textView, textView.string == original else { return }
                Self.applyFormattedCode(tidied, original: original, to: textView)
            }
            return
        }

        let tidied = CodeFormatter.tidy(original, language: language)
        Self.applyFormattedCode(tidied, original: original, to: textView)
    }

    /// Applies an already-computed format result through the text view's native edit
    /// cycle, preserving delegate updates and undo behavior.
    private static func applyFormattedCode(
        _ tidied: String, original: String, to textView: NSTextView
    ) {
        guard tidied != original else { return }
        let whole = NSRange(location: 0, length: (original as NSString).length)
        guard textView.shouldChangeText(in: whole, replacementString: tidied) else { return }
        textView.textStorage?.replaceCharacters(in: whole, with: tidied)
        textView.didChangeText()  // fires the delegate → writes back to config.code
        textView.undoManager?.setActionName(String(localized: "Format Code"))
    }

    /// The code editor's `NSTextView` in `window`, found by the accessibility identifier
    /// `CodeEditorView` assigns it. Used so Format Code edits the real text view (and its
    /// undo stack) rather than mutating the model behind its back.
    private static func editorTextView(in window: NSWindow?) -> NSTextView? {
        guard let root = window?.contentView else { return nil }
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let textView = view as? NSTextView,
                textView.accessibilityIdentifier() == "code-editor-text-view"
            {
                return textView
            }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }
}
