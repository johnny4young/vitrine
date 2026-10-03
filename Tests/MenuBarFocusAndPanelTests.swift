import AppKit
import Foundation
import KeyboardShortcuts
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

/// Focus hand-back, panel state, and single-instance rules around the menu-bar panel.
@MainActor
@Suite("Menu-bar focus and panel state")
struct MenuBarFocusAndPanelTests {
    @Test func focusReturnsOnlyWhenVitrineIsActiveAndWindowless() {
        #expect(
            AppActivation.shouldRestoreFocus(
                previousProcessID: 42, appIsActive: true, hasVisibleAppWindow: false,
                appProcessID: 7, helperProcessID: 9))
        // A panel action opened a window: keep it focused.
        #expect(
            !AppActivation.shouldRestoreFocus(
                previousProcessID: 42, appIsActive: true, hasVisibleAppWindow: true,
                appProcessID: 7, helperProcessID: 9))
        // The user already clicked into another app.
        #expect(
            !AppActivation.shouldRestoreFocus(
                previousProcessID: 42, appIsActive: false, hasVisibleAppWindow: false,
                appProcessID: 7, helperProcessID: 9))
        #expect(
            !AppActivation.shouldRestoreFocus(
                previousProcessID: 9, appIsActive: true, hasVisibleAppWindow: false,
                appProcessID: 7, helperProcessID: 9))
        #expect(
            !AppActivation.shouldRestoreFocus(
                previousProcessID: nil, appIsActive: true, hasVisibleAppWindow: false))
    }

    @Test func helperAnchorsOnTheIconRatherThanThePointer() {
        let pointer = CGPoint(x: 10, y: 10)
        let frame = CGRect(x: 1200, y: 1050, width: 24, height: 24)
        #expect(
            MenuBarHelperContract.anchorLocation(buttonWindowFrame: frame, mouseLocation: pointer)
                == CGPoint(x: 1212, y: 1062))
        #expect(
            MenuBarHelperContract.anchorLocation(buttonWindowFrame: nil, mouseLocation: pointer)
                == pointer)
    }

    @Test func aRelaunchIgnoresTheInstanceItReplaces() {
        let predecessor = AppDelegate.RunningInstance(
            processID: 100, isTerminated: false, isHelper: false)
        let current = AppDelegate.RunningInstance(
            processID: 200, isTerminated: false, isHelper: false)
        let helper = AppDelegate.RunningInstance(
            processID: 300, isTerminated: false, isHelper: true)
        let arguments = ["Vitrine", AppRelauncher.predecessorArgument(for: 100)]

        #expect(AppRelauncher.predecessorProcessID(in: arguments) == 100)
        #expect(
            AppDelegate.existingInstance(
                among: [predecessor, current, helper], currentProcessID: 200,
                predecessorProcessID: AppRelauncher.predecessorProcessID(in: arguments)) == nil)
        // A plain second launch still defers to the running copy.
        #expect(
            AppDelegate.existingInstance(
                among: [predecessor, current], currentProcessID: 200, predecessorProcessID: nil)
                == 100)
        let terminated = AppDelegate.RunningInstance(
            processID: 100, isTerminated: true, isHelper: false)
        #expect(
            AppDelegate.existingInstance(
                among: [terminated, current], currentProcessID: 200, predecessorProcessID: nil)
                == nil)
        #expect(AppRelauncher.predecessorProcessID(in: ["Vitrine", "--relaunch-of=x"]) == nil)
    }

    @Test func hotkeyChipRefreshesAndNamesWhatTheHotkeyRuns() {
        let state = MenuBarPanelState()
        state.refresh(hotkeyAction: .quickCapture, shortcut: nil)
        #expect(state.hotkeyGlyphs == nil)

        let shortcut = KeyboardShortcuts.Shortcut(.v, modifiers: [.command, .control])
        state.refresh(hotkeyAction: .openEditor, shortcut: shortcut)
        #expect(state.hotkeyGlyphs == shortcut.description)
        #expect(state.hotkeyPurpose == MenuBarPanelState.hotkeyPurpose(for: .openEditor))
        #expect(
            MenuBarPanelState.hotkeyPurpose(for: .openEditor)
                != MenuBarPanelState.hotkeyPurpose(for: .quickCapture))
    }

    @Test func panelRowsShowTheNewestCaptureEvenWithThreePins() {
        let now = Date()
        var pinned: [Capture] = (0..<3).map { index in
            var capture = Capture(code: "pinned \(index)", languageID: "swift", themeID: "one-dark")
            capture.isPinned = true
            capture.date = now.addingTimeInterval(-Double(100 + index))
            return capture
        }
        var newest = Capture(code: "newest", languageID: "swift", themeID: "one-dark")
        newest.date = now
        pinned.append(newest)

        let rows = MenuBarContent.panelCaptures(from: pinned)
        #expect(rows.count == 3)
        #expect(rows.first?.id == newest.id)
    }

    @Test func panelActionsCloseThePanelBeforeTheyRun() async {
        var events: [String] = []
        let dismiss = MenuBarDismissAction { events.append("dismiss") }

        let task = dismiss.thenRun { events.append("capture") }
        #expect(events == ["dismiss"])
        await task.value

        #expect(events == ["dismiss", "capture"])
    }

    @Test func hudFeedbackIsAnnouncedWithFailuresUrgent() {
        var announced: [CaptureHUDController.Announcement] = []
        let controller = CaptureHUDController(postAnnouncement: { announced.append($0) })

        controller.announce(Notifier.feedback(for: .copied))
        controller.announce(Notifier.feedback(for: .empty))

        #expect(
            announced.map(\.message) == [
                Notifier.feedback(for: .copied).message, Notifier.feedback(for: .empty).message,
            ])
        #expect(announced.map(\.isUrgent) == [false, true])
    }
}

/// File ▸ Copy Image follows the same close-after-copy rule as the toolbar.
@MainActor
@Suite("Editor copy command")
struct EditorCopyCommandTests {
    private func makeSettings(closeAfterCopy: Bool) -> AppSettings {
        let settings = AppSettings(defaults: testDefaults())
        settings.config.code = "let x = 1"
        settings.export.closeAfterCopy = closeAfterCopy
        settings.export.richClipboard = false
        settings.export.textSidecar = false
        return settings
    }

    @Test func copyClosesTheEditorWhenThePreferenceIsOn() async throws {
        let settings = makeSettings(closeAfterCopy: true)
        let responder = EditorCommandResponder(
            settings: settings, feedback: .noOp, presentation: .noOp)
        let window = CloseRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false

        let close = try #require(
            responder.copyImage(
                from: settings, editorWindow: window, pasteboard: NSPasteboard.withUniqueName()))
        await close.value

        #expect(window.didClose)
    }

    @Test func copyKeepsTheEditorWhenThePreferenceIsOff() {
        let settings = makeSettings(closeAfterCopy: false)
        let responder = EditorCommandResponder(
            settings: settings, feedback: .noOp, presentation: .noOp)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled],
            backing: .buffered, defer: true)

        #expect(
            responder.copyImage(
                from: settings, editorWindow: window, pasteboard: NSPasteboard.withUniqueName())
                == nil)
    }
}

/// Window placement shared by every window controller.
@Suite("Window placement")
struct WindowPlacementTests {
    @Test func aComparisonBoardSizedWindowFitsASmallDisplay() {
        let visible = CGRect(x: 0, y: 0, width: 1024, height: 743)
        let frame = WindowPlacement.centeredFrame(
            CGRect(x: 0, y: 0, width: 1080, height: 748), in: visible)

        #expect(visible.contains(frame))
        #expect(frame.width == 1024)
        #expect(frame.midY == visible.midY)
    }

    @Test func debugConstraintNarrowsAroundTheCenter() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let narrowed = WindowPlacement.constrained(visible, maxWidth: 800, maxHeight: nil)
        #expect(narrowed.width == 800)
        #expect(narrowed.midX == visible.midX)
        #expect(narrowed.height == visible.height)
    }
}

private final class CloseRecordingWindow: NSWindow {
    private(set) var didClose = false

    override func close() {
        didClose = true
        super.close()
    }
}
