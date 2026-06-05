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
    case settings
    case help
    case about

    // Editor/document-scoped (dispatched through the first responder so they are
    // enabled only while an editor window is key, and only when it has code).
    case copyImage
    case saveImage
    case shareImage

    /// The menu-item title. Trailing ellipsis marks a command that opens further
    /// UI before completing (a save panel, the share sheet, a window), matching
    /// macOS Human Interface Guidelines.
    var title: String {
        switch self {
        case .newCapture: "New Capture from Clipboard"
        case .openEditor: "Open Editor"
        case .settings: "Settings…"
        case .help: "Vitrine Help"
        case .about: "About Vitrine"
        case .copyImage: "Copy Image"
        case .saveImage: "Save Image…"
        case .shareImage: "Share Image…"
        }
    }

    /// The SF Symbol shared with the equivalent toolbar item, so a command reads
    /// the same in the menu and the toolbar (CS-032 "toolbar items have
    /// equivalent menu commands").
    var systemImageName: String {
        switch self {
        case .newCapture: "camera.viewfinder"
        case .openEditor: "macwindow"
        case .settings: "gearshape"
        case .help: "questionmark.circle"
        case .about: "info.circle"
        case .copyImage: "doc.on.clipboard"
        case .saveImage: "square.and.arrow.down"
        case .shareImage: "square.and.arrow.up"
        }
    }

    /// The lowercase key for the menu item's key equivalent, or `nil` for a
    /// command with no shortcut. Lowercase letters with `.command` are the macOS
    /// convention; AppKit renders the glyph (e.g. ⌘E) automatically.
    var keyEquivalent: String? {
        switch self {
        case .newCapture: "s"  // ⇧⌘S — global quick capture
        case .openEditor: "e"  // ⌘E — open the editor
        case .settings: ","  // ⌘, — the standard Settings shortcut
        case .help: "?"  // ⌘? — the standard Help shortcut
        case .about: nil  // About conventionally has no shortcut
        case .copyImage: "c"  // ⇧⌘C — copy the rendered image (plain ⌘C stays text copy)
        case .saveImage: "s"  // ⌘S — save the rendered image
        case .shareImage: nil  // Share opens a picker; no reserved shortcut
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
        case .openEditor, .settings, .help, .saveImage: [.command]
        case .about, .shareImage: []
        }
    }

    /// A stable accessibility identifier for the menu item, used by UI tests and
    /// VoiceOver navigation. Never localized (CS-032 / CS-047).
    var accessibilityIdentifier: String { "command-\(rawValue)" }

    /// A concise VoiceOver description. Kept short and action-first so VoiceOver
    /// reads usefully without repeating the menu hierarchy (CS-032 "VoiceOver
    /// labels are concise and useful").
    var accessibilityLabel: String {
        switch self {
        case .newCapture: "New capture from clipboard"
        case .openEditor: "Open editor"
        case .settings: "Settings"
        case .help: "Vitrine help"
        case .about: "About Vitrine"
        case .copyImage: "Copy image to clipboard"
        case .saveImage: "Save image to a file"
        case .shareImage: "Share image"
        }
    }
}

extension VitrineCommand {
    /// Editor/document-scoped commands, enabled only when an editor window is key
    /// and it has code to render.
    static let editorCommands: [VitrineCommand] = [.copyImage, .saveImage, .shareImage]

    /// Whether this command acts on the editor and so is enabled only when an
    /// editor is the key window.
    var isEditorScoped: Bool { Self.editorCommands.contains(self) }
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
/// window is key *and* it currently holds code, which `canPerform(_:)` decides.
final class EditorCommandResponder: NSObject, NSMenuItemValidation {
    static let shared = EditorCommandResponder()

    private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
        super.init()
    }

    /// Whether `command` can run right now. The editor commands require the
    /// editor window to be key (so a Save/Share initiated from the menu acts on
    /// the visible editor) and require code to render.
    func canPerform(_ command: VitrineCommand) -> Bool {
        guard command.isEditorScoped else { return true }
        return isEditorKey && !settings.config.code.isEmpty
    }

    /// True when the key (or, failing that, the main) window is the editor. The
    /// fallback to `mainWindow` keeps the command usable when focus sits in a
    /// panel the editor presented; `EditorWindowController` tags its window with
    /// the `editor-window` identifier.
    private var isEditorKey: Bool {
        let window = NSApp.keyWindow ?? NSApp.mainWindow
        return window?.accessibilityIdentifier() == "editor-window"
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(copyRenderedImage(_:)): canPerform(.copyImage)
        case #selector(saveRenderedImage(_:)): canPerform(.saveImage)
        case #selector(shareRenderedImage(_:)): canPerform(.shareImage)
        default: true
        }
    }

    @objc func copyRenderedImage(_ sender: Any?) {
        guard canPerform(.copyImage) else { return }
        ExportManager.copyToPasteboard(
            settings.config, scale: CGFloat(settings.effectiveExportScale),
            fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile)
    }

    @objc func saveRenderedImage(_ sender: Any?) {
        guard canPerform(.saveImage) else { return }
        ExportManager.saveToFile(
            settings.config, scale: CGFloat(settings.effectiveExportScale),
            format: settings.exportFormat, fixedSize: settings.effectiveFixedSize,
            profile: settings.colorProfile)
    }

    @objc func shareRenderedImage(_ sender: Any?) {
        guard canPerform(.shareImage),
            let image = ExportManager.renderNSImage(
                settings.config, scale: CGFloat(settings.effectiveExportScale),
                fixedSize: settings.effectiveFixedSize, profile: settings.colorProfile),
            let view = NSApp.keyWindow?.contentView
        else { return }
        ShareManager.share(image, relativeTo: view)
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

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowManager.shared.show()
    }

    @objc func showHelp(_ sender: Any?) {
        // No web dependency: until CS-049 ships in-app Help content, route Help to
        // the Settings ▸ About pane, which carries the app's identity, version,
        // and privacy summary. This keeps the Help command reachable and offline.
        SettingsWindowManager.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }
}

// MARK: - Main menu builder

/// Builds the application main menu from `VitrineCommand` and installs it on
/// `NSApp.mainMenu` (CS-032).
///
/// Because Vitrine is an agent app with no `WindowGroup`, AppKit shows no menu
/// bar until one is provided. Assigning this menu gives the editor and settings
/// windows a complete, conventional menu bar — including the standard Edit menu
/// (Undo/Cut/Copy/Paste/Select All) whose first-responder actions drive the code
/// text view — so every important command is discoverable and keyboard-reachable.
enum AppMenu {
    /// Assembles and assigns the main menu. Safe to call once at launch.
    @MainActor
    static func install() {
        NSApp.mainMenu = make()
    }

    /// Builds the menu tree. Separated from `install()` so its structure can be
    /// inspected in tests without a running app.
    @MainActor
    static func make() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        return mainMenu
    }

    /// A menu item wired to a `VitrineCommand`: title, shortcut, target, and a
    /// stable accessibility identifier all come from the command, so the menu and
    /// the equivalent toolbar item cannot drift.
    private static func item(
        for command: VitrineCommand, action: Selector, target: AnyObject
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: command.title, action: action, keyEquivalent: command.keyEquivalent ?? "")
        menuItem.keyEquivalentModifierMask = command.modifiers
        menuItem.target = target
        menuItem.image = NSImage(
            systemSymbolName: command.systemImageName, accessibilityDescription: nil)
        menuItem.setAccessibilityIdentifier(command.accessibilityIdentifier)
        menuItem.setAccessibilityLabel(command.accessibilityLabel)
        return menuItem
    }

    // MARK: App menu (bold, named after the app)

    private static func appMenuItem() -> NSMenuItem {
        let appMenuItem = NSMenuItem()
        let menu = NSMenu()

        menu.addItem(
            item(
                for: .about, action: #selector(AppCommandResponder.showAbout(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(.separator())
        menu.addItem(
            item(
                for: .settings, action: #selector(AppCommandResponder.openSettings(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(.separator())

        // Standard Services submenu, so system Services are available like any
        // other Mac app.
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())

        menu.addItem(
            withTitle: "Hide Vitrine", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Vitrine", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        appMenuItem.submenu = menu
        return appMenuItem
    }

    // MARK: File menu (capture / editor / export)

    private static func fileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let menu = NSMenu(title: "File")

        menu.addItem(
            item(
                for: .newCapture,
                action: #selector(AppCommandResponder.newCaptureFromClipboard(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(
            item(
                for: .openEditor, action: #selector(AppCommandResponder.openEditor(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(.separator())

        // Editor-scoped export commands. They mirror the editor toolbar and are
        // enabled only when the editor is key and has code (see
        // `EditorCommandResponder.validateMenuItem`).
        menu.addItem(
            item(
                for: .copyImage, action: #selector(EditorCommandResponder.copyRenderedImage(_:)),
                target: EditorCommandResponder.shared))
        menu.addItem(
            item(
                for: .saveImage, action: #selector(EditorCommandResponder.saveRenderedImage(_:)),
                target: EditorCommandResponder.shared))
        menu.addItem(
            item(
                for: .shareImage, action: #selector(EditorCommandResponder.shareRenderedImage(_:)),
                target: EditorCommandResponder.shared))
        menu.addItem(.separator())

        let close = NSMenuItem(
            title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        menu.addItem(close)

        fileMenuItem.submenu = menu
        return fileMenuItem
    }

    // MARK: Edit menu (standard first-responder text actions)

    private static func editMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")

        // First-responder targets (`nil`): AppKit routes these to the focused
        // text view, giving the code editor real Undo/Cut/Copy/Paste/Select All
        // with their conventional shortcuts.
        menu.addItem(
            withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(
            title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = menu
        return editMenuItem
    }

    // MARK: View menu (full-screen / standard window view commands)

    private static func viewMenuItem() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let menu = NSMenu(title: "View")
        let fullScreen = NSMenuItem(
            title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullScreen)
        viewMenuItem.submenu = menu
        return viewMenuItem
    }

    // MARK: Window menu (standard, AppKit-managed)

    private static func windowMenuItem() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let menu = NSMenu(title: "Window")
        menu.addItem(
            withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        menu.addItem(
            withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Bring All to Front",
            action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = menu
        // AppKit auto-populates and manages the Window menu's window list.
        NSApp.windowsMenu = menu
        return windowMenuItem
    }

    // MARK: Help menu

    private static func helpMenuItem() -> NSMenuItem {
        let helpMenuItem = NSMenuItem()
        let menu = NSMenu(title: "Help")
        menu.addItem(
            item(
                for: .help, action: #selector(AppCommandResponder.showHelp(_:)),
                target: AppCommandResponder.shared))
        helpMenuItem.submenu = menu
        // AppKit shows the searchable Help field at the top of this menu.
        NSApp.helpMenu = menu
        return helpMenuItem
    }
}
