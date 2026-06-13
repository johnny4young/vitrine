import AppKit

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
    /// The menu most recently assembled by `install()`, kept so
    /// `reinstallIfDisplaced()` can tell "still ours" from "replaced" on the hot
    /// `applicationWillUpdate(_:)` path.
    private(set) static var installed: NSMenu?

    /// The first top-level item of `installed`. SwiftUI's scene bring-up does not
    /// swap `NSApp.mainMenu` for its own instance — it replaces the *items* of
    /// whatever menu is installed (see `reinstallIfDisplaced()`), which an identity
    /// check on the menu alone cannot detect. When that happens this item is
    /// removed from the menu, so `sentinel?.menu !== installed` flags the takeover.
    private static var sentinel: NSMenuItem?

    /// Assembles and assigns the main menu. Called at launch, and again by
    /// `reinstallIfDisplaced()` whenever something has taken the menu over.
    @MainActor
    static func install() {
        let menu = make()
        installed = menu
        sentinel = menu.items.first
        NSApp.mainMenu = menu
    }

    /// Puts the designed menu back when SwiftUI has taken `NSApp.mainMenu` over.
    ///
    /// SwiftUI's `MenuBarExtra` scene bring-up installs its own default main menu
    /// *after* `applicationDidFinishLaunching` — and it does so by replacing the
    /// items of the currently installed menu in place, not by assigning a new
    /// `NSMenu`. That silently drops the designed File and Edit menus and kills the
    /// key equivalents that route through them, while `NSApp.mainMenu` still
    /// compares identical to the menu `install()` assigned. The takeover is
    /// detected instead by `sentinel`, the designed menu's first item, which the
    /// in-place replacement evicts.
    ///
    /// Called from `applicationWillUpdate(_:)` on every event-loop pass, so the
    /// common case is two pointer comparisons; the rebuild runs only on an actual
    /// takeover (once, at scene bring-up). A no-op until the launch-time
    /// `install()` has run, so it cannot install a menu before the delegate meant
    /// to. Rebuilding (rather than re-adding the old items) also re-points
    /// `NSApp.servicesMenu`/`windowsMenu`/`helpMenu`, which SwiftUI re-claimed.
    @MainActor
    static func reinstallIfDisplaced() {
        guard let installed else { return }
        if NSApp.mainMenu === installed, sentinel?.menu === installed { return }
        Log.app.notice("Main menu was taken over; reinstalling the designed menu")
        install()
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

        // "Check for Updates…" sits in its conventional App-menu position, but only on
        // the direct-download build that ships Sparkle (CS-064). The App Store build
        // excludes Sparkle, so `isSupported` is false and no update command appears.
        if SoftwareUpdater.isSupported {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    for: .checkForUpdates,
                    action: #selector(AppCommandResponder.checkForUpdates(_:)),
                    target: AppCommandResponder.shared))
        }

        menu.addItem(.separator())
        menu.addItem(
            item(
                for: .settings, action: #selector(AppCommandResponder.openSettings(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(.separator())

        // Standard Services submenu, so system Services are available like any
        // other Mac app.
        let services = NSMenuItem(
            title: String(localized: "Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())

        menu.addItem(
            withTitle: String(localized: "Hide Vitrine"),
            action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"
        )
        let hideOthers = NSMenuItem(
            title: String(localized: "Hide Others"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(
            withTitle: String(localized: "Show All"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Vitrine"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")

        appMenuItem.submenu = menu
        return appMenuItem
    }

    // MARK: File menu (capture / editor / export)

    private static func fileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem()
        let menu = NSMenu(title: String(localized: "File"))

        menu.addItem(
            item(
                for: .newCapture,
                action: #selector(AppCommandResponder.newCaptureFromClipboard(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(
            item(
                for: .openEditor, action: #selector(AppCommandResponder.openEditor(_:)),
                target: AppCommandResponder.shared))
        // Open an additional, independent editor window (CS-053).
        menu.addItem(
            item(
                for: .newEditorWindow,
                action: #selector(AppCommandResponder.newEditorWindow(_:)),
                target: AppCommandResponder.shared))
        // Open the social-card editor — the local 1200×630 card composer (CS-041).
        menu.addItem(
            item(
                for: .newSocialCard,
                action: #selector(AppCommandResponder.openSocialCardEditor(_:)),
                target: AppCommandResponder.shared))
        // Open the Web Snapshot editor — local HTML + gated URL capture (CS-042/043).
        menu.addItem(
            item(
                for: .newWebSnapshot,
                action: #selector(AppCommandResponder.openWebSnapshotEditor(_:)),
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

        // Promote the key editor window's style to the app-wide default (CS-053).
        // Editor-scoped but code-independent, so it is enabled whenever an editor is key.
        menu.addItem(
            item(
                for: .makeDefault, action: #selector(EditorCommandResponder.makeWindowDefault(_:)),
                target: EditorCommandResponder.shared))
        menu.addItem(.separator())

        let close = NSMenuItem(
            title: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        menu.addItem(close)

        fileMenuItem.submenu = menu
        return fileMenuItem
    }

    // MARK: Edit menu (standard first-responder text actions)

    private static func editMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Edit"))

        // First-responder targets (`nil`): AppKit routes these to the focused
        // text view, giving the code editor real Undo/Cut/Copy/Paste/Select All
        // with their conventional shortcuts.
        menu.addItem(
            withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(
            title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)),
            keyEquivalent: "x")
        menu.addItem(
            withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)),
            keyEquivalent: "c")
        menu.addItem(
            withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)),
            keyEquivalent: "v")
        menu.addItem(
            withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a")
        menu.addItem(.separator())
        // Format Code (CS-049). Unlike the first-responder text actions above, this is an
        // editor command with an explicit target + validation; it mirrors the editor
        // toolbar's Format button so the menu and toolbar stay in lockstep (CS-032).
        menu.addItem(
            item(
                for: .formatCode, action: #selector(EditorCommandResponder.formatCode(_:)),
                target: EditorCommandResponder.shared))

        editMenuItem.submenu = menu
        return editMenuItem
    }

    // MARK: View menu (full-screen / standard window view commands)

    private static func viewMenuItem() -> NSMenuItem {
        let viewMenuItem = NSMenuItem()
        let menu = NSMenu(title: String(localized: "View"))
        let fullScreen = NSMenuItem(
            title: String(localized: "Enter Full Screen"),
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullScreen)
        viewMenuItem.submenu = menu
        return viewMenuItem
    }

    // MARK: Window menu (standard, AppKit-managed)

    private static func windowMenuItem() -> NSMenuItem {
        let windowMenuItem = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Window"))
        menu.addItem(
            withTitle: String(localized: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m")
        menu.addItem(
            withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = menu
        // AppKit auto-populates and manages the Window menu's window list.
        NSApp.windowsMenu = menu
        return windowMenuItem
    }

    // MARK: Help menu

    private static func helpMenuItem() -> NSMenuItem {
        let helpMenuItem = NSMenuItem()
        let menu = NSMenu(title: String(localized: "Help"))
        menu.addItem(
            item(
                for: .help, action: #selector(AppCommandResponder.showHelp(_:)),
                target: AppCommandResponder.shared))
        menu.addItem(
            item(
                for: .whatsNew, action: #selector(AppCommandResponder.showWhatsNew(_:)),
                target: AppCommandResponder.shared))
        helpMenuItem.submenu = menu
        // AppKit shows the searchable Help field at the top of this menu.
        NSApp.helpMenu = menu
        return helpMenuItem
    }
}
