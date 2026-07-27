import AppKit
import Foundation
import Testing

@testable import Vitrine

/// Guards the menu-bar affordance the whole app hangs off.
///
/// The regressions these cover are severe and silent. A SwiftUI `MenuBarExtra` could
/// terminate the windowless app when its item was hidden; an in-process `NSStatusItem`
/// kept the process alive but could still remain unpainted. Production now gives the
/// painted item a fresh helper-process identity while the main app retains the panel.
@MainActor
@Suite("Menu-bar status item")
struct MenuBarStatusItemTests {
    /// A suite of its own, so the assertions never depend on — or disturb — the defaults
    /// of the app hosting these tests.
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "menubar-tests-\(name)")!
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSStatusItem") {
            defaults.removeObject(forKey: key)
        }
        return defaults
    }

    @Test func repairClearsAPersistedHiddenStateForBothKeyForms() {
        let defaults = isolatedDefaults(#function)
        // The exact state macOS persists once the icon is hidden.
        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-0")
        defaults.set(false, forKey: "NSStatusItem Visible Item-0")

        StatusItemController.repairVisibilityDefaults(in: defaults)

        #expect(defaults.bool(forKey: "NSStatusItem VisibleCC Item-0"))
        #expect(defaults.bool(forKey: "NSStatusItem Visible Item-0"))
    }

    @Test func repairCoversEveryAutosaveNameTheSceneCouldHavePicked() {
        let defaults = isolatedDefaults(#function)
        StatusItemController.repairVisibilityDefaults(in: defaults)

        for autosaveName in StatusItemController.repairedAutosaveNames {
            #expect(
                defaults.bool(forKey: "NSStatusItem VisibleCC \(autosaveName)"),
                "a stale hidden state under \(autosaveName) re-creates the launch trap")
            #expect(defaults.bool(forKey: "NSStatusItem Visible \(autosaveName)"))
        }
    }

    /// Both the deterministic AppKit identity and the former SwiftUI identity must stay
    /// covered so an upgrade can repair either persistence shape.
    @Test func repairIncludesCurrentAndHistoricalNames() {
        #expect(
            StatusItemController.repairedAutosaveNames.contains(StatusItemController.autosaveName))
        #expect(StatusItemController.repairedAutosaveNames.contains("Item-0"))
    }

    @Test func attachInstallsOneVisibleFixedItemAndIsIdempotent() throws {
        let controller = StatusItemController()
        #expect(!controller.isAttached)

        controller.attach()
        #expect(controller.isAttached)
        let item = try #require(controller.statusItem)
        #expect(item.autosaveName == StatusItemController.autosaveName)
        #expect(item.length == NSStatusItem.squareLength)
        #expect(item.behavior.isEmpty)
        #expect(item.isVisible)
        #expect(item.button?.image != nil)
        #expect(item.button?.bounds.width ?? 0 > 0)

        // A second call must not stack a duplicate icon.
        controller.attach()
        #expect(controller.statusItem === item)
        #expect(controller.isAttached)

        controller.detach()
        #expect(!controller.isAttached)
    }

    /// Control Center finishes hosting the button after `attach()` returns. Simulate
    /// that asynchronous transition overwriting the live state and prove the bounded
    /// post-materialization pass repairs it.
    @Test func delayedRepairRestoresVisibilityAfterHosting() async throws {
        let controller = StatusItemController(visibilityRepairDelays: [.milliseconds(10)])
        controller.attach()
        let item = try #require(controller.statusItem)
        item.isVisible = false

        try await Task.sleep(for: .milliseconds(50))

        #expect(item.isVisible)
        #expect(
            UserDefaults.standard.bool(
                forKey: "NSStatusItem VisibleCC \(StatusItemController.autosaveName)"))
        controller.detach()
    }

    @Test func productionUsesTheHelperWithoutLeakingItIntoTests() {
        #expect(AppDelegate.menuBarOwner(for: [:]) == .helper)
        #expect(
            AppDelegate.menuBarOwner(
                for: ["XCTestConfigurationFilePath": "/tmp/VitrineTests.xctestconfiguration"])
                == .disabled)
        #expect(
            AppDelegate.menuBarOwner(for: ["VITRINE_USER_DEFAULTS_SUITE": "ui-tests"])
                == .inProcess)
        #expect(
            AppDelegate.menuBarOwner(
                for: [
                    "VITRINE_USER_DEFAULTS_SUITE": "manual-review",
                    "VITRINE_FORCE_MENU_BAR_HELPER": "1",
                ]) == .helper)
    }

    @Test func helperAnchorRoundTripsAcrossDisplayCoordinates() throws {
        let original = MenuBarAnchor(
            appProcessID: 123,
            helperProcessID: 456,
            sessionToken: "88B0A8F4-1BDD-4555-9C18-0AD8014CE55A",
            clickLocation: CGPoint(x: -1_248.5, y: 1_067.25))

        let decoded = try #require(MenuBarAnchor(encoded: original.encoded))

        #expect(decoded == original)
    }

    @Test func helperAnchorRejectsMalformedOrUnboundedValues() {
        #expect(MenuBarAnchor(encoded: "123|456||10|20") == nil)
        #expect(MenuBarAnchor(encoded: "0|456|token|10|20") == nil)
        #expect(MenuBarAnchor(encoded: "123|-1|token|10|20") == nil)
        #expect(MenuBarAnchor(encoded: "123|456|token|nan|20") == nil)
        #expect(MenuBarAnchor(encoded: "123|456|token|10|inf") == nil)
    }

    @Test func panelAnchorMustBelongToACurrentDisplay() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            CGRect(x: -1_280, y: 0, width: 1_280, height: 1_024),
        ]

        #expect(
            StatusItemController.isValidAnchorLocation(
                CGPoint(x: 1_000, y: 1_000), screenFrames: frames))
        #expect(
            StatusItemController.isValidAnchorLocation(
                CGPoint(x: -640, y: 1_000), screenFrames: frames))
        #expect(
            !StatusItemController.isValidAnchorLocation(
                CGPoint(x: 4_000, y: 1_000), screenFrames: frames))
        #expect(
            !StatusItemController.isValidAnchorLocation(
                CGPoint(x: CGFloat.infinity, y: 10), screenFrames: frames))
    }

    /// The panel must not have a timer-driven lifetime. Vitrine owns dismissal so the
    /// helper's opening event can be excluded from outside-interaction monitoring.
    @Test func panelUsesApplicationDefinedDismissal() {
        #expect(StatusItemController.popoverBehavior == .applicationDefined)
    }

    @Test func onlyActivatedProcessesOutsideTheAppAndHelperDismissThePanel() {
        let appProcessID: pid_t = 101
        let helperProcessID: pid_t = 202

        #expect(
            !StatusItemController.shouldDismissForActivatedProcess(
                appProcessID,
                appProcessID: appProcessID,
                helperProcessID: helperProcessID))
        #expect(
            !StatusItemController.shouldDismissForActivatedProcess(
                helperProcessID,
                appProcessID: appProcessID,
                helperProcessID: helperProcessID))
        #expect(
            StatusItemController.shouldDismissForActivatedProcess(
                303,
                appProcessID: appProcessID,
                helperProcessID: helperProcessID))
    }

    @Test func globalPointerDismissalExcludesTheHelperIcon() {
        let anchor = CGRect(x: 900, y: 1_050, width: 24, height: 24)

        #expect(
            !StatusItemController.shouldDismissForGlobalPointer(
                at: CGPoint(x: anchor.midX, y: anchor.midY),
                anchorFrame: anchor))
        #expect(
            StatusItemController.shouldDismissForGlobalPointer(
                at: CGPoint(x: 400, y: 400),
                anchorFrame: anchor))
        #expect(
            StatusItemController.shouldDismissForGlobalPointer(
                at: CGPoint(x: 400, y: 400),
                anchorFrame: nil))
    }

    @Test func escapeIsTheOnlyKeyThatDismissesThePanelDirectly() {
        #expect(StatusItemController.shouldDismissForKeyCode(53))
        #expect(!StatusItemController.shouldDismissForKeyCode(36))
        #expect(!StatusItemController.shouldDismissForKeyCode(49))
    }

    /// The helper-presence monitor calls `detach()` every two seconds to ensure the
    /// in-process fallback is absent. With no fallback item, that housekeeping must not
    /// close the helper-owned panel.
    @Test func detachingAnAbsentFallbackKeepsTheHelperPanelOpen() throws {
        let screen = try #require(NSScreen.screens.first)
        let anchor = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 12)
        let controller = StatusItemController()

        controller.togglePanel(at: anchor)
        #expect(controller.isPanelShown)
        #expect(controller.externalAnchorSurvivesDeactivation)

        controller.detach()
        #expect(controller.isPanelShown)
        #expect(controller.externalAnchorSurvivesDeactivation)
    }

    /// The panel's rows call `dismiss()`; with the popover behind it that must run the
    /// injected close action rather than SwiftUI's own (which cannot close an
    /// AppKit-presented popover).
    @Test func dismissActionRunsTheInjectedClosure() {
        var closed = 0
        let dismiss = MenuBarDismissAction { closed += 1 }

        dismiss()
        dismiss()

        #expect(closed == 2)
    }

    /// Building the panel without a popover behind it (previews, tests) must stay safe:
    /// the default action has nothing to close and must simply do nothing.
    @Test func theDefaultDismissActionIsANoOp() {
        var sideEffects = 0
        let observed = MenuBarDismissAction { sideEffects += 1 }

        MenuBarDismissAction()()
        MenuBarContent().dismiss()

        #expect(sideEffects == 0, "only the injected action may run")
        observed()
        #expect(sideEffects == 1)
    }

    /// A source guard: the SwiftUI scene is what made a hidden icon fatal, so its return
    /// would silently restore the crash. Checked against the repo, not a built bundle.
    @Test func theAppDoesNotVendItsMenuBarItemThroughASwiftUIScene() throws {
        let appSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Vitrine/App/VitrineApp.swift")
        let source = try String(contentsOf: appSource, encoding: .utf8)

        // Mentions in prose explain the history; a scene declaration would reintroduce it.
        #expect(
            !source.contains("MenuBarExtra(\""),
            "the menu bar must stay owned by the AppKit helper/fallback path")
        #expect(!source.contains(".menuBarExtraStyle"))
    }
}
