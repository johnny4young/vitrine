import AppKit
import KeyboardShortcuts
import SwiftUI
import Testing
import VitrineRendering

@testable import Vitrine

@Suite("Hotkey conflict")
struct HotkeyConflictTests {
    private let shortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift])

    private func menu(_ key: String, _ modifiers: NSEvent.ModifierFlags) -> NSMenu {
        let root = NSMenu()
        let parent = root.addItem(withTitle: "File", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(withTitle: "New Capture", action: nil, keyEquivalent: key)
            .keyEquivalentModifierMask = modifiers
        parent.submenu = submenu
        return root
    }

    @Test func aFreeShortcutReportsNothing() {
        let conflict = HotkeyConflict.find(
            for: shortcut, systemShortcuts: [.init(.k, modifiers: [.command])],
            mainMenu: menu("k", [.command]))
        #expect(conflict == nil)
    }

    @Test(arguments: [("s", NSEvent.ModifierFlags.command.union(.shift)), ("S", .command)])
    func aMenuCommandIsNamedWhicheverWayItSpellsShift(
        key: String, modifiers: NSEvent.ModifierFlags
    ) {
        let conflict = HotkeyConflict.find(
            for: shortcut, systemShortcuts: [], mainMenu: menu(key, modifiers))
        #expect(conflict == .menuCommand(title: "New Capture"))
    }

    @Test func modifiersMustMatchExactly() {
        let conflict = HotkeyConflict.find(
            for: shortcut, systemShortcuts: [], mainMenu: menu("s", [.command]))
        #expect(conflict == nil)
    }

    @Test func anEnabledSystemShortcutIsReported() {
        let conflict = HotkeyConflict.find(
            for: shortcut, systemShortcuts: [shortcut], mainMenu: NSMenu())
        #expect(conflict == .macOSShortcut)
    }

    @Test func aMenuCommandWinsOverTheSystemLikeTheRecorder() {
        let conflict = HotkeyConflict.find(
            for: shortcut, systemShortcuts: [shortcut],
            mainMenu: menu("s", [.command, .shift]))
        #expect(conflict == .menuCommand(title: "New Capture"))
    }

    @Test func bareF12IsNotReportedLikeTheRecorder() {
        let f12 = KeyboardShortcuts.Shortcut(.f12)
        #expect(HotkeyConflict.find(for: f12, systemShortcuts: [f12], mainMenu: nil) == nil)
    }

    @Test func anAcknowledgedMacOSShortcutIsNotReported() {
        let conflict = HotkeyConflict.find(
            for: shortcut, systemShortcuts: [shortcut], mainMenu: NSMenu(), acknowledged: shortcut)
        #expect(conflict == nil)
    }

    @Test func anAcknowledgementDoesNotCoverAnotherShortcutOrAMenuCommand() {
        let other = KeyboardShortcuts.Shortcut(.k, modifiers: [.command])
        #expect(
            HotkeyConflict.find(
                for: shortcut, systemShortcuts: [shortcut], mainMenu: NSMenu(), acknowledged: other)
                == .macOSShortcut)
        #expect(
            HotkeyConflict.find(
                for: shortcut, systemShortcuts: [shortcut],
                mainMenu: menu("s", [.command, .shift]), acknowledged: shortcut)
                == .menuCommand(title: "New Capture"))
    }

    @Test func recordingAMacOSShortcutAcknowledgesItAcrossLaunchesUntilChanged() {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.noteRecordedHotkey(shortcut, systemShortcuts: [shortcut])
        #expect(settings.acknowledgedMacOSHotkey == shortcut)
        #expect(AppSettings(defaults: defaults).acknowledgedMacOSHotkey == shortcut)

        settings.noteRecordedHotkey(.init(.k, modifiers: [.command]), systemShortcuts: [shortcut])
        #expect(settings.acknowledgedMacOSHotkey == nil)
        #expect(AppSettings(defaults: defaults).acknowledgedMacOSHotkey == nil)
    }

    @Test func clearingTheRecorderOrResettingForgetsTheAcknowledgement() {
        let settings = AppSettings(defaults: testDefaults())
        settings.noteRecordedHotkey(shortcut, systemShortcuts: [shortcut])
        settings.noteRecordedHotkey(nil, systemShortcuts: [shortcut])
        #expect(settings.acknowledgedMacOSHotkey == nil)

        settings.noteRecordedHotkey(shortcut, systemShortcuts: [shortcut])
        settings.resetToDefaults()
        #expect(settings.acknowledgedMacOSHotkey == nil)
    }

    @Test func handleStartsRecordingInTheField() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let field = KeyboardShortcuts.RecorderCocoa(for: .init("hotkey-conflict-tests"))
        window.contentView?.addSubview(field)
        defer { field.removeFromSuperview() }

        let handle = HotkeyRecorderHandle()
        handle.field = field
        handle.beginRecording()
        let editor = try #require(field.currentEditor())
        #expect(window.firstResponder === editor)
    }
}

@Suite("Locked Brand Kit preview")
struct BrandKitLockedPreviewTests {
    @Test func theRendererDrawsTheMarkOntoTheSample() throws {
        let image = try #require(BrandKitLockedPreview.render())
        var unbranded = BrandKitLockedPreview.config
        unbranded.watermark = nil
        let plain = try #require(
            ExportManager.renderNSImage(
                unbranded, scale: 2, fixedSize: BrandKitLockedPreview.canvasSize, budget: .preview))
        #expect(image.tiffRepresentation != plain.tiffRepresentation)
    }
}

@Suite("Library preset row")
struct LibraryPresetRowTests {
    /// The menu is the only route to Rename and Delete, so a long saved name must not widen
    /// the section past the pane and push it out. Measured as layout: macOS 27 draws the picker
    /// and menu itself, without the NSPopUpButtons macOS 26 hosts.
    @Test func aLongPresetNameKeepsTheActionsMenuInsideThePane() throws {
        let defaults = testDefaults()
        let settings = AppSettings(defaults: defaults)
        let store = PresetStore(defaults: defaults)
        _ = store.savePreset(named: String(repeating: "W", count: 60), from: settings.config)

        let host = NSHostingView(
            rootView: StylePresetsSection(
                settings: settings, store: store, themes: CustomThemeStore(defaults: defaults)))
        // A popup lists its items, and so takes their width, only once it has been laid out.
        let paneWidth: CGFloat = 478
        host.frame = NSRect(x: 0, y: 0, width: paneWidth, height: 200)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= paneWidth)
    }
}
