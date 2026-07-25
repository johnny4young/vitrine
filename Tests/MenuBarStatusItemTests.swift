import AppKit
import Foundation
import Testing

@testable import Vitrine

/// Guards the menu-bar affordance the whole app hangs off.
///
/// The regression these cover is severe and silent: with a SwiftUI `MenuBarExtra`
/// scene, a persisted "hidden" state for its Control Center-hosted status item made
/// macOS 26 remove the item moments after launch, and AppKit terminated the agent on
/// that removal — the app exited 0 with no icon, no window, and no crash report, and the
/// unit-test host (this same bundle) died before XCTest could connect.
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

    /// `Item-0` is what SwiftUI's scene actually named its item, so it is the one name
    /// the repair can never drop.
    @Test func repairIncludesTheNameTheSwiftUISceneUsed() {
        #expect(StatusItemController.repairedAutosaveNames.contains("Item-0"))
    }

    @Test func attachInstallsExactlyOneItemAndIsIdempotent() {
        let controller = StatusItemController()
        #expect(!controller.isAttached)

        controller.attach()
        #expect(controller.isAttached)

        // A second call must not stack a duplicate icon.
        controller.attach()
        #expect(controller.isAttached)

        controller.detach()
        #expect(!controller.isAttached)
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
            "the menu bar must stay owned by StatusItemController, not a MenuBarExtra scene")
        #expect(!source.contains(".menuBarExtraStyle"))
    }
}
