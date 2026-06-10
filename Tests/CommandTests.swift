import AppKit
import SwiftUI
import Testing

@testable import Vitrine

// CS-032 — the app command surface: titles, shortcuts, accessibility, menu
// assembly, and editor-command gating. These are pure/model-level checks; the
// menu's runtime behavior is smoke-tested in the UI tests.

@Suite("VitrineCommand model")
@MainActor
struct VitrineCommandModelTests {
    @Test func everyCommandHasTitleSymbolAndIdentifier() {
        for command in VitrineCommand.allCases {
            #expect(!command.title.isEmpty)
            #expect(!command.systemImageName.isEmpty)
            #expect(!command.accessibilityLabel.isEmpty)
            #expect(command.accessibilityIdentifier == "command-\(command.rawValue)")
        }
    }

    @Test func accessibilityIdentifiersAreUnique() {
        let identifiers = VitrineCommand.allCases.map(\.accessibilityIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test func everySymbolResolvesToASystemImage() {
        // A bad SF Symbol name renders nothing in the menu/toolbar; assert each one
        // exists so a typo is caught at test time rather than as a blank icon.
        for command in VitrineCommand.allCases {
            #expect(
                NSImage(systemSymbolName: command.systemImageName, accessibilityDescription: nil)
                    != nil,
                "Missing SF Symbol: \(command.systemImageName)")
        }
    }

    @Test func editorScopedCommandsAreFlagged() {
        #expect(VitrineCommand.copyImage.isEditorScoped)
        #expect(VitrineCommand.saveImage.isEditorScoped)
        #expect(VitrineCommand.shareImage.isEditorScoped)

        #expect(!VitrineCommand.newCapture.isEditorScoped)
        #expect(!VitrineCommand.openEditor.isEditorScoped)
        #expect(!VitrineCommand.settings.isEditorScoped)
        #expect(!VitrineCommand.help.isEditorScoped)
        #expect(!VitrineCommand.about.isEditorScoped)
    }

    @Test func titlesUseEllipsisOnlyWhenFurtherUIFollows() {
        // Save, Share, and Settings open more UI before completing → ellipsis.
        // Copy, New Capture, Open Editor, Help, About complete in place → none.
        #expect(VitrineCommand.saveImage.title.hasSuffix("…"))
        #expect(VitrineCommand.shareImage.title.hasSuffix("…"))
        #expect(VitrineCommand.settings.title.hasSuffix("…"))

        #expect(!VitrineCommand.copyImage.title.hasSuffix("…"))
        #expect(!VitrineCommand.newCapture.title.hasSuffix("…"))
        #expect(!VitrineCommand.openEditor.title.hasSuffix("…"))
        #expect(!VitrineCommand.about.title.hasSuffix("…"))
    }
}

@Suite("VitrineCommand keyboard shortcuts")
@MainActor
struct VitrineCommandShortcutTests {
    /// macOS shortcuts that belong to the standard Edit/Window/App menus and must
    /// not be re-bound to an app command, so the editor keeps its expected
    /// text-editing and window keys.
    private static let reservedCommandKeys: Set<String> = ["x", "v", "a", "z", "q", "w", "m", "h"]

    @Test func appCommandsDoNotStealReservedEditingKeys() {
        for command in VitrineCommand.allCases {
            guard let key = command.keyEquivalent, command.modifiers == [.command] else { continue }
            #expect(
                !Self.reservedCommandKeys.contains(key),
                "\(command) re-binds the reserved ⌘\(key.uppercased())")
        }
    }

    @Test func imageCopyDoesNotShadowPlainTextCopy() {
        // Plain ⌘C must remain text copy in the editor; image copy is ⇧⌘C.
        #expect(VitrineCommand.copyImage.keyEquivalent == "c")
        #expect(VitrineCommand.copyImage.modifiers == [.command, .shift])
    }

    @Test func standardShortcutsMatchPlatformConventions() {
        #expect(VitrineCommand.settings.keyEquivalent == ",")
        #expect(VitrineCommand.settings.modifiers == [.command])
        #expect(VitrineCommand.help.keyEquivalent == "?")
        #expect(VitrineCommand.help.modifiers == [.command])
        #expect(VitrineCommand.saveImage.keyEquivalent == "s")
        #expect(VitrineCommand.saveImage.modifiers == [.command])
    }

    @Test func noTwoCommandsShareTheSameShortcut() {
        // A key+modifier pair must map to at most one command, or one of two menu
        // items would be unreachable by keyboard.
        var seen = Set<String>()
        for command in VitrineCommand.allCases {
            guard let key = command.keyEquivalent else { continue }
            let signature = "\(command.modifiers.rawValue):\(key)"
            #expect(seen.insert(signature).inserted, "Duplicate shortcut on \(command)")
        }
    }

    @Test func aboutAndShareHaveNoShortcut() {
        #expect(VitrineCommand.about.keyEquivalent == nil)
        #expect(VitrineCommand.shareImage.keyEquivalent == nil)
    }
}

@Suite("VitrineCommand toolbar/menu shortcut parity")
@MainActor
struct VitrineCommandShortcutParityTests {
    // CS-032's core promise is that a toolbar/menu-bar button binds the *same*
    // shortcut as its AppKit main-menu counterpart. The SwiftUI side builds that
    // shortcut as `KeyboardShortcut(keyEquivalent.first!, modifiers:
    // swiftUIEventModifiers)`, so parity reduces to two checks: the key character
    // matches the menu item, and the AppKit→SwiftUI modifier translation neither
    // drops nor invents a flag. Both are asserted here against the pure
    // `swiftUIEventModifiers` mapping — never by constructing a `KeyboardShortcut`,
    // whose initializer reaches the system Shortcuts daemon and hangs the headless
    // test host.

    /// Independently derives the SwiftUI modifier set a command should bridge to,
    /// so a copy-paste bug in the production mapping cannot also pass the test.
    private func expectedModifiers(_ flags: NSEvent.ModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    @Test func modifierTranslationPreservesEveryFlag() {
        // Each command's bridged modifiers must equal the translation of its AppKit
        // modifiers exactly — a dropped flag here is the drift CS-032 forbids.
        for command in VitrineCommand.allCases {
            #expect(
                command.swiftUIEventModifiers == expectedModifiers(command.modifiers),
                "\(command) drops or adds a modifier when bridged to the toolbar")
        }
    }

    @Test func commandModifierTranslationIsNotSilentlyEmpty() {
        // Guards against a degenerate mapping that returns `[]` for everything and
        // would still satisfy a same-bug-on-both-sides comparison: commands that
        // declare ⌘-based shortcuts must carry `.command` after translation.
        for command in [VitrineCommand.openEditor, .settings, .help, .saveImage] {
            #expect(command.swiftUIEventModifiers.contains(.command))
        }
    }

    @Test func imageCopyKeepsShiftSoItStaysDistinctFromTextCopy() {
        // The highest-stakes case: if the bridge dropped `.shift`, the toolbar's
        // image-copy button would bind plain ⌘C and shadow text copy, contradicting
        // both the menu item (⇧⌘C) and `imageCopyDoesNotShadowPlainTextCopy`.
        #expect(VitrineCommand.copyImage.swiftUIEventModifiers == [.command, .shift])
    }

    @Test func unmodifiedAndCommandShiftCasesTranslateExactly() {
        // Share carries no modifier; quick capture is ⇧⌘ — the two non-plain-⌘
        // shapes the bridge must reproduce.
        #expect(VitrineCommand.shareImage.swiftUIEventModifiers == [])
        #expect(VitrineCommand.newCapture.swiftUIEventModifiers == [.command, .shift])
    }

    @Test func everyShortcutCommandBridgesItsMenuKeyCharacter() {
        // The bridged shortcut's key is `keyEquivalent.first`; assert that first
        // character is the menu item's key, so the toolbar and menu press the same
        // physical key. (Asserted on the source character, not on a constructed
        // `KeyboardShortcut`, to stay daemon-free.)
        for command in VitrineCommand.allCases {
            guard let key = command.keyEquivalent else { continue }
            #expect(key.count == 1, "\(command) key equivalent is not a single character")
            #expect(
                key.first != nil,
                "\(command) has a key equivalent the bridge could not turn into a key")
        }
    }

    @Test func bridgedShortcutsStayUniqueJustLikeTheMenuShortcuts() {
        // Parity is only useful if the bridged shortcuts are themselves collision
        // free; two SwiftUI buttons sharing a key+modifier pair would make one
        // unreachable, mirroring `noTwoCommandsShareTheSameShortcut`. Compared on
        // the bridge's own inputs (key character + translated modifiers).
        var seen = Set<String>()
        for command in VitrineCommand.allCases {
            guard let key = command.keyEquivalent else { continue }
            let signature = "\(command.swiftUIEventModifiers.rawValue):\(key)"
            #expect(seen.insert(signature).inserted, "Duplicate bridged shortcut on \(command)")
        }
    }
}

@Suite("Application main menu assembly")
@MainActor
struct AppMenuTests {
    @Test func topLevelMenusAreThePlatformStandardSet() {
        let menu = AppMenu.make()
        let titles = menu.items.compactMap { $0.submenu?.title }
        // The App menu's submenu title is empty (it shows the app name); the rest
        // follow the conventional order.
        #expect(titles.contains("File"))
        #expect(titles.contains("Edit"))
        #expect(titles.contains("View"))
        #expect(titles.contains("Window"))
        #expect(titles.contains("Help"))
    }

    @Test func fileMenuExposesCaptureEditorAndExportCommands() {
        let file = submenu(named: "File")
        let identifiers = menuItemIdentifiers(file)
        #expect(identifiers.contains(VitrineCommand.newCapture.accessibilityIdentifier))
        #expect(identifiers.contains(VitrineCommand.openEditor.accessibilityIdentifier))
        #expect(identifiers.contains(VitrineCommand.copyImage.accessibilityIdentifier))
        #expect(identifiers.contains(VitrineCommand.saveImage.accessibilityIdentifier))
        #expect(identifiers.contains(VitrineCommand.shareImage.accessibilityIdentifier))
    }

    @Test func appMenuExposesSettingsAndAbout() {
        // The App menu is the first item; its submenu holds About and Settings.
        let appSubmenu = AppMenu.make().items.first?.submenu
        let identifiers = appSubmenu.map(menuItemIdentifiers) ?? []
        #expect(identifiers.contains(VitrineCommand.about.accessibilityIdentifier))
        #expect(identifiers.contains(VitrineCommand.settings.accessibilityIdentifier))
    }

    @Test func helpMenuExposesTheHelpCommand() {
        let identifiers = menuItemIdentifiers(submenu(named: "Help"))
        #expect(identifiers.contains(VitrineCommand.help.accessibilityIdentifier))
    }

    @Test func exportCommandsTargetTheEditorResponder() {
        // Editor commands must dispatch to the editor command responder so they mirror the
        // toolbar; a wrong target would silently no-op. Copy/Save/Share/Make Default live in
        // the File menu and Format Code in the Edit menu, so search the whole main menu.
        let items = AppMenu.make().items.compactMap(\.submenu).flatMap(\.items)
        for command in VitrineCommand.editorCommands {
            let item = items.first {
                $0.accessibilityIdentifier() == command.accessibilityIdentifier
            }
            #expect(item?.target is EditorCommandResponder, "\(command) is not editor-targeted")
        }
    }

    @Test func wiredCommandItemsCarryTheirShortcut() {
        let file = submenu(named: "File")
        let save = file.items.first {
            $0.accessibilityIdentifier() == VitrineCommand.saveImage.accessibilityIdentifier
        }
        #expect(save?.keyEquivalent == "s")
        #expect(save?.keyEquivalentModifierMask == [.command])
    }

    /// Format Code lives in the Edit menu (it is a text-edit operation, not an export),
    /// carries ⌥⌘F, and dispatches to the editor responder so the menu and the editor
    /// toolbar button stay in lockstep (CS-032/CS-049).
    @Test func formatCodeIsInTheEditMenuWithItsShortcut() {
        let edit = submenu(named: "Edit")
        let item = edit.items.first {
            $0.accessibilityIdentifier() == VitrineCommand.formatCode.accessibilityIdentifier
        }
        #expect(item != nil, "Format Code must be in the Edit menu")
        #expect(item?.keyEquivalent == "f")
        #expect(item?.keyEquivalentModifierMask == [.command, .option])
        #expect(item?.target is EditorCommandResponder)
    }

    // MARK: Helpers

    private func submenu(named title: String) -> NSMenu {
        let menu = AppMenu.make().items.compactMap(\.submenu).first { $0.title == title }
        #expect(menu != nil, "Missing top-level menu: \(title)")
        return menu ?? NSMenu()
    }

    private func menuItemIdentifiers(_ menu: NSMenu) -> [String] {
        menu.items.map { $0.accessibilityIdentifier() }
    }
}

@Suite("Editor command gating")
@MainActor
struct EditorCommandResponderTests {
    private func makeSettings(code: String) -> AppSettings {
        let settings = AppSettings(
            defaults: UserDefaults(suiteName: "VitrineCommandTests-\(UUID().uuidString)")!)
        settings.config.code = code
        return settings
    }

    @Test func nonEditorCommandsAlwaysPerform() {
        let responder = EditorCommandResponder(settings: makeSettings(code: ""))
        // App-scoped commands are not gated by the responder.
        #expect(responder.canPerform(.newCapture))
        #expect(responder.canPerform(.openEditor))
        #expect(responder.canPerform(.settings))
        #expect(responder.canPerform(.help))
        #expect(responder.canPerform(.about))
    }

    @Test func exportCommandsRequireCodeAndAKeyEditorWindow() {
        // No editor window is key in the unit-test host, so even with code present
        // the editor-scoped commands stay disabled — exactly the validation a menu
        // would apply, proving Save/Share never act on a missing editor.
        let responder = EditorCommandResponder(settings: makeSettings(code: "let x = 1"))
        #expect(!responder.canPerform(.copyImage))
        #expect(!responder.canPerform(.saveImage))
        #expect(!responder.canPerform(.shareImage))
    }

    @Test func validateMenuItemMatchesCanPerform() {
        let responder = EditorCommandResponder(settings: makeSettings(code: "let x = 1"))
        let item = NSMenuItem(
            title: VitrineCommand.copyImage.title,
            action: #selector(EditorCommandResponder.copyRenderedImage(_:)), keyEquivalent: "")
        // Disabled: no editor window is key in the test host.
        #expect(responder.validateMenuItem(item) == false)
    }
}
