import AppKit

/// The app's command surface: every important action, its title, SF Symbol,
/// keyboard shortcut, and accessibility identifier in one place (CS-032).
///
/// Vitrine is a menu-bar agent (`LSUIElement`) whose only SwiftUI scene is the
/// `MenuBarExtra`; it has no `WindowGroup`, so SwiftUI's `.commands` modifier has
/// no main menu to populate. Instead `AppMenu` builds a real `NSMenu` main menu
/// from these commands and installs it on `NSApp.mainMenu`, so that whenever the
/// editor or settings window is key the full menu bar — App ▸, File ▸, Edit ▸,
/// View ▸, Window ▸, Help ▸ — is available with standard keyboard handling and
/// Full Keyboard Access.
///
/// Keeping the title/shortcut/identifier here (rather than scattered across the
/// menu builder, the toolbar, and the UI tests) means the menu command and the
/// equivalent toolbar item never drift, and a unit test can assert the shortcut
/// set is internally consistent and free of conflicts with reserved macOS
/// shortcuts.
enum VitrineCommand: String, CaseIterable {
    // App-scoped (always available)
    case newCapture
    case openEditor
    case newEditorWindow
    // Opens the social-card editor — a local, deterministic 1200×630 card composed
    // from the same theme/background/font vocabulary as a snapshot (CS-041).
    case newSocialCard
    // Opens the Web Snapshot editor — local HTML rendering and (on a build with the
    // network entitlement) URL capture (CS-042/CS-043).
    case newWebSnapshot
    case settings
    case help
    case about
    case whatsNew
    // Direct-download auto-update (CS-064). Surfaced only on the direct-download
    // build, which ships Sparkle; the App Store build excludes Sparkle and hides
    // this command (see SoftwareUpdater).
    case checkForUpdates

    // Editor/document-scoped (dispatched through the first responder so they are
    // enabled only while an editor window is key, and only when it has code).
    case copyImage
    case saveImage
    case shareImage
    case makeDefault
    // Tidy the editor's code — re-indent JSON / strip the common leading indentation
    // (CS-049). Editor-scoped and code-requiring; mirrors the editor toolbar's Format
    // button so the menu command and the button stay in lockstep (CS-032).
    case formatCode

    // Editor copy-submenu options (CS-054 rich export): reached from the editor's
    // copy-options menu; no global key equivalent.
    case copyDataURI
    case copyHighlightedCode

    /// The menu-item title. Trailing ellipsis marks a command that opens further
    /// UI before completing (a save panel, the share sheet, a window), matching
    /// macOS Human Interface Guidelines.
    ///
    /// The title is resolved through the String Catalog (CS-047): it is shown both
    /// in an AppKit `NSMenuItem` (which needs a plain `String`) and, via `Label`,
    /// in SwiftUI surfaces, so it is localized here rather than relying on SwiftUI's
    /// implicit `LocalizedStringKey` at only one of those call sites.
    var title: String {
        switch self {
        case .newCapture: String(localized: "New Capture from Clipboard")
        case .openEditor: String(localized: "Open Editor")
        case .newEditorWindow: String(localized: "New Editor Window")
        // No ellipsis: like Open Editor, it opens its window directly (the card is
        // composed in that window, not behind a further dialog).
        case .newSocialCard: String(localized: "New Social Card")
        case .newWebSnapshot: String(localized: "New Web Snapshot")
        case .settings: String(localized: "Settings…")
        case .help: String(localized: "Vitrine Help")
        case .about: String(localized: "About Vitrine")
        case .whatsNew: String(localized: "What's New")
        case .checkForUpdates: String(localized: "Check for Updates…")
        case .copyImage: String(localized: "Copy Image")
        case .saveImage: String(localized: "Save Image…")
        case .shareImage: String(localized: "Share Image…")
        case .makeDefault: String(localized: "Make This Window the Default")
        case .formatCode: String(localized: "Format Code")
        case .copyDataURI: String(localized: "Copy as Data URI")
        case .copyHighlightedCode: String(localized: "Copy Highlighted Code")
        }
    }

    /// The SF Symbol shared with the equivalent toolbar item, so a command reads
    /// the same in the menu and the toolbar (CS-032 "toolbar items have
    /// equivalent menu commands").
    var systemImageName: String {
        switch self {
        case .newCapture: "camera.viewfinder"
        case .openEditor: "macwindow"
        case .newEditorWindow: "macwindow.badge.plus"
        case .newSocialCard: "photo.artframe"
        case .newWebSnapshot: "globe"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        case .whatsNew: "sparkles"
        case .checkForUpdates: "arrow.down.circle"
        case .copyImage: "doc.on.clipboard"
        case .saveImage: "square.and.arrow.down"
        case .shareImage: "square.and.arrow.up"
        case .makeDefault: "star"
        case .formatCode: "text.alignleft"
        case .copyDataURI: "curlybraces"
        case .copyHighlightedCode: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// The lowercase key for the menu item's key equivalent, or `nil` for a
    /// command with no shortcut. Lowercase letters with `.command` are the macOS
    /// convention; AppKit renders the glyph (e.g. ⌘E) automatically.
    var keyEquivalent: String? {
        switch self {
        case .newCapture: "s"  // ⇧⌘S — global quick capture
        case .openEditor: "e"  // ⌘E — open the editor
        case .newEditorWindow: "n"  // ⌘N — open an additional editor window
        case .settings: ","  // ⌘, — the standard Settings shortcut
        case .help: "?"  // ⌘? — the standard Help shortcut
        case .about: nil  // About conventionally has no shortcut
        case .copyImage: "c"  // ⇧⌘C — copy the rendered image (plain ⌘C stays text copy)
        case .saveImage: "s"  // ⌘S — save the rendered image
        case .shareImage: nil  // Share opens a picker; no reserved shortcut
        case .formatCode: "f"  // ⌥⌘F — tidy the code (⌘F stays free for find)
        // Submenu/window/explicit-action commands with no reserved shortcut.
        case .copyDataURI, .copyHighlightedCode, .whatsNew, .makeDefault, .checkForUpdates,
            .newSocialCard, .newWebSnapshot:
            nil
        }
    }

    /// The modifier flags paired with `keyEquivalent`. Deliberately avoids
    /// colliding with the editor's own text shortcuts: image copy is ⇧⌘C so the
    /// plain ⌘C still copies selected text, and quick capture is ⇧⌘S so the
    /// editor's ⌘S can mean "save image" without ambiguity.
    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .newCapture: [.command, .shift]
        case .copyImage: [.command, .shift]
        case .formatCode: [.command, .option]
        case .openEditor, .newEditorWindow, .settings, .help, .saveImage: [.command]
        case .about, .shareImage, .makeDefault, .copyDataURI, .copyHighlightedCode, .whatsNew,
            .checkForUpdates, .newSocialCard, .newWebSnapshot:
            []
        }
    }

    /// A stable accessibility identifier for the menu item, used by UI tests and
    /// VoiceOver navigation. Never localized (CS-032 / CS-047).
    var accessibilityIdentifier: String { "command-\(rawValue)" }

    /// A concise VoiceOver description. Kept short and action-first so VoiceOver
    /// reads usefully without repeating the menu hierarchy (CS-032 "VoiceOver
    /// labels are concise and useful"). Localized through the String Catalog
    /// (CS-047); the accessibility *identifier* above stays non-localized.
    var accessibilityLabel: String {
        switch self {
        case .newCapture: String(localized: "New capture from clipboard")
        case .openEditor: String(localized: "Open editor")
        case .newEditorWindow: String(localized: "Open a new editor window")
        case .newSocialCard: String(localized: "New social card")
        case .newWebSnapshot: String(localized: "New web snapshot")
        case .settings: String(localized: "Settings")
        case .help: String(localized: "Vitrine help")
        case .about: String(localized: "About Vitrine")
        case .whatsNew: String(localized: "What's new in Vitrine")
        case .checkForUpdates: String(localized: "Check for app updates")
        case .copyImage: String(localized: "Copy image to clipboard")
        case .saveImage: String(localized: "Save image to a file")
        case .shareImage: String(localized: "Share image")
        case .makeDefault: String(localized: "Make this window's style the default")
        case .formatCode: String(localized: "Format the code")
        case .copyDataURI: String(localized: "Copy image as a base64 data URI")
        case .copyHighlightedCode: String(localized: "Copy syntax-highlighted code")
        }
    }
}

extension VitrineCommand {
    /// Editor-render commands, enabled only when an editor window is key *and* it has
    /// visible content to render. Copy / Save / Share each turn the document into an
    /// image, so an empty editor leaves them disabled; a beautified foreground image is
    /// renderable even when the code editor is empty.
    static let editorRenderCommands: [VitrineCommand] = [.copyImage, .saveImage, .shareImage]

    /// Editor commands that need source text present to act. Format Code has nothing to
    /// tidy on an empty buffer (CS-049), and it stays code-only even when the editor is
    /// showing a beautified foreground image.
    static let codeRequiringCommands: [VitrineCommand] = [.formatCode]

    /// All editor/document-scoped commands, enabled only when an editor window is key.
    /// "Make Default" is editor-scoped but code-independent: adopting a window's style
    /// as the app default is meaningful even before any code is typed (CS-053).
    static let editorCommands: [VitrineCommand] =
        editorRenderCommands + codeRequiringCommands + [.makeDefault]

    /// Whether this command acts on the editor and so is enabled only when an editor is
    /// the key window.
    var isEditorScoped: Bool { Self.editorCommands.contains(self) }

    /// Whether this command additionally requires visible content (code or a foreground
    /// image) to render, as opposed to merely requiring an editor to be key.
    var requiresRenderableContent: Bool { Self.editorRenderCommands.contains(self) }

    /// Whether this command additionally requires the editor to hold source text, as
    /// opposed to a beautified image or an empty editor.
    var requiresCode: Bool { Self.codeRequiringCommands.contains(self) }
}

// MARK: - Editor command target

/// Performs and validates the editor/document commands (Copy / Save / Share
/// Image) so they exist as real menu commands with keyboard shortcuts, not just
/// toolbar buttons (CS-032). These mirror the editor toolbar exactly: both reach
/// the shared `AppSettings` and `ExportManager`, so the menu command and the
/// toolbar button always produce the same image.
///
/// A single shared instance is the explicit target of the editor menu items.
/// Targeting it directly (rather than the responder chain) keeps enablement
/// deterministic and unit-testable: a command is enabled only when an editor
/// window is key — and, for the render commands, only when that window holds
/// code — which `canPerform(_:)` decides.
///
/// ## Multi-window (CS-053)
///
/// With more than one editor open, a menu command must act on whichever editor is
/// *key*, not on a fixed instance. The responder therefore resolves the key window's
/// own `EditorSession` at action time (``activeSettings``) and operates on its
/// per-window config, falling back to the injected `settings` when no editor session
/// is resolvable (the unit-test host, where no real window is key). "Make Default"
/// promotes that key window's style to the app-wide default.
final class EditorCommandResponder: NSObject, NSMenuItemValidation {
    static let shared = EditorCommandResponder()

    private let settings: AppSettings

    /// Small snippets format synchronously so the menu command feels instant. Larger
    /// snippets do the pure string work off the main actor and only return to AppKit
    /// for the final text replacement; beyond this cap, formatting is refused instead
    /// of risking an unresponsive editor.
    private static let asyncFormatThresholdBytes = 64 * 1024
    private static let maxInteractiveFormatBytes = 1 * 1024 * 1024

    init(settings: AppSettings = .shared) {
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

    /// True when the key (or, failing that, the main) window is an editor. The fallback
    /// to `mainWindow` keeps the command usable when focus sits in a panel the editor
    /// presented; `EditorWindowController` tags every editor window with an
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
        default: true
        }
    }

    @objc func copyRenderedImage(_ sender: Any?) {
        guard canPerform(.copyImage) else { return }
        let settings = activeSettings
        // Surface the outcome so a render/encode failure from the menu isn't silent
        // (CS-038), mirroring the quick-capture HUD path.
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

    /// Promotes the key editor window's current style to the app-wide default (CS-053).
    /// A no-op when no editor window is key, so it cannot adopt a phantom configuration.
    @objc func makeWindowDefault(_ sender: Any?) {
        guard canPerform(.makeDefault),
            let session = EditorWindowController.shared.keyWindowSession
        else { return }
        session.makeDefault()
    }

    /// Tidies the key editor's code in place (CS-049): JSON is pretty-printed, brace and
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

// MARK: - App command target

/// Performs the app-scoped commands (New Capture, Open Editor, Settings, Help,
/// About) from the main menu. A small `@objc` target rather than free functions
/// so menu items can wire to selectors and AppKit's standard validation applies.
final class AppCommandResponder: NSObject {
    static let shared = AppCommandResponder()

    @objc func newCaptureFromClipboard(_ sender: Any?) {
        QuickCapture.perform(settings: .shared)
    }

    @objc func openEditor(_ sender: Any?) {
        EditorWindowController.shared.show()
    }

    /// Opens an additional, independent editor window (CS-053).
    @objc func newEditorWindow(_ sender: Any?) {
        EditorWindowController.shared.openNewWindow()
    }

    /// Opens the social-card editor — the local 1200×630 card composer (CS-041).
    @objc func openSocialCardEditor(_ sender: Any?) {
        SocialCardWindowController.shared.show()
    }

    /// Opens the Web Snapshot editor — local HTML rendering and gated URL capture
    /// (CS-042/CS-043). Routed through `WebSnapshotPresenter` so this command surface
    /// carries no dependency on the WebKit-backed window (which the CLI excludes).
    @objc func openWebSnapshotEditor(_ sender: Any?) {
        WebSnapshotPresenter.show()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowManager.shared.show()
    }

    @objc func showHelp(_ sender: Any?) {
        HelpWindowController.shared.show()
    }

    @objc func showWhatsNew(_ sender: Any?) {
        WhatsNewWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        AboutPanel.present()
    }

    /// Restyles the key editor window's theme from the View ▸ Theme submenu (or the
    /// app-wide default when no editor is key), so a theme is one click from the menu
    /// bar. The chosen theme id rides on the menu item's `representedObject`.
    @objc func selectTheme(_ sender: Any?) {
        guard let item = sender as? NSMenuItem, let themeID = item.representedObject as? String
        else { return }
        let theme = CustomThemeStore.shared.theme(withID: themeID)
        let target = EditorWindowController.shared.keyWindowSession?.settings ?? .shared
        target.config.theme = theme
    }

    /// Starts a user-initiated update check on the direct-download build (CS-064). The
    /// menu item that targets this is only added on a build that ships Sparkle, so on the
    /// App Store build (which excludes Sparkle) there is no item and `checkForUpdates()`
    /// degrades to a no-op.
    @objc func checkForUpdates(_ sender: Any?) {
        SoftwareUpdater.shared.checkForUpdates()
    }
}
