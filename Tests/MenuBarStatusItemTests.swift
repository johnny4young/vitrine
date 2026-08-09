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
    /// A store of its own, so the assertions never depend on — or disturb — the defaults
    /// of the app hosting these tests.
    private func isolatedDefaults() -> UserDefaults {
        let defaults = testDefaults()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSStatusItem") {
            defaults.removeObject(forKey: key)
        }
        return defaults
    }

    @Test func repairClearsAPersistedHiddenStateForBothKeyForms() {
        let defaults = isolatedDefaults()
        // The exact state macOS persists once the icon is hidden.
        defaults.set(false, forKey: "NSStatusItem VisibleCC Item-0")
        defaults.set(false, forKey: "NSStatusItem Visible Item-0")

        StatusItemController.repairVisibilityDefaults(in: defaults)

        #expect(defaults.bool(forKey: "NSStatusItem VisibleCC Item-0"))
        #expect(defaults.bool(forKey: "NSStatusItem Visible Item-0"))
    }

    @Test func repairCoversEveryAutosaveNameTheSceneCouldHavePicked() {
        let defaults = isolatedDefaults()
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
        let controller = StatusItemController(
            environment: AppEnvironment(defaults: isolatedDefaults()),
            feedback: CaptureFeedbackPresenter(),
            navigation: .noOp)
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
        let controller = StatusItemController(
            environment: AppEnvironment(defaults: isolatedDefaults()),
            feedback: CaptureFeedbackPresenter(),
            navigation: .noOp,
            visibilityRepairDelays: [.milliseconds(10)])
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

    @Test func helperConfigurationAcceptsOnlyAPositivePIDAndUUIDToken() throws {
        let token = "88B0A8F4-1BDD-4555-9C18-0AD8014CE55A"
        let configuration = try #require(
            MenuBarHelperConfiguration(arguments: ["VitrineMenuBarHelper", "123", token]))

        #expect(configuration.appProcessID == 123)
        #expect(configuration.sessionToken == token)

        for invalidArguments in [
            ["VitrineMenuBarHelper"],
            ["VitrineMenuBarHelper", "123"],
            ["VitrineMenuBarHelper", "123", token, "extra"],
            ["VitrineMenuBarHelper", "not-a-pid", token],
            ["VitrineMenuBarHelper", "0", token],
            ["VitrineMenuBarHelper", "-1", token],
            ["VitrineMenuBarHelper", "123", ""],
            ["VitrineMenuBarHelper", "123", "not-a-uuid"],
            ["VitrineMenuBarHelper", "123", String(repeating: "x", count: 129)],
        ] {
            #expect(
                MenuBarHelperConfiguration(arguments: invalidArguments) == nil,
                "helper must reject malformed invocation: \(invalidArguments)")
        }
    }

    @Test func helperOwnerMustMatchTheExactPIDAndContainingBundle() {
        let expectedBundle = URL(fileURLWithPath: "/Applications/Vitrine.app")
        let executable = expectedBundle.appendingPathComponent("Contents/MacOS/Vitrine")

        #expect(
            MenuBarHelperContract.isExpectedOwner(
                candidateProcessID: 123,
                candidateExecutableURL: executable,
                candidateBundleURL: expectedBundle,
                expectedProcessID: 123,
                currentProcessID: 456,
                expectedBundleURL: expectedBundle))

        let mismatches: [(pid_t, URL?, URL?, pid_t, pid_t, URL)] = [
            (999, executable, expectedBundle, 123, 456, expectedBundle),
            (123, executable, expectedBundle, 123, 123, expectedBundle),
            (
                123,
                expectedBundle.appendingPathComponent(
                    "Contents/MacOS/\(MenuBarHelperContract.executableName)"),
                expectedBundle,
                123,
                456,
                expectedBundle
            ),
            (
                123, executable, URL(fileURLWithPath: "/Applications/Vitrine Beta.app"),
                123, 456, expectedBundle
            ),
            (123, nil, expectedBundle, 123, 456, expectedBundle),
            (123, executable, nil, 123, 456, expectedBundle),
        ]
        for mismatch in mismatches {
            #expect(
                !MenuBarHelperContract.isExpectedOwner(
                    candidateProcessID: mismatch.0,
                    candidateExecutableURL: mismatch.1,
                    candidateBundleURL: mismatch.2,
                    expectedProcessID: mismatch.3,
                    currentProcessID: mismatch.4,
                    expectedBundleURL: mismatch.5))
        }
    }

    @Test func helperWatchdogRequiresBothItsIconAndOwner() {
        #expect(
            MenuBarHelperContract.shouldRemainRunning(
                statusItemVisible: true, ownerExists: true))
        #expect(
            !MenuBarHelperContract.shouldRemainRunning(
                statusItemVisible: false, ownerExists: true))
        #expect(
            !MenuBarHelperContract.shouldRemainRunning(
                statusItemVisible: true, ownerExists: false))
        #expect(
            !MenuBarHelperContract.shouldRemainRunning(
                statusItemVisible: false, ownerExists: false))
    }

    @Test func appAndHelperVisibilityRepairsShareTheHistoricalContract() {
        #expect(
            StatusItemController.autosaveName == MenuBarStatusItemVisibility.primaryAutosaveName)
        #expect(MenuBarHelperLauncher.executableName == MenuBarHelperContract.executableName)

        for currentName in [
            MenuBarStatusItemVisibility.primaryAutosaveName,
            MenuBarStatusItemVisibility.helperAutosaveName,
        ] {
            let defaults = isolatedDefaults()
            MenuBarStatusItemVisibility.repair(
                in: defaults,
                currentAutosaveName: currentName)
            let names = MenuBarStatusItemVisibility.repairedAutosaveNames(
                currentAutosaveName: currentName)

            #expect(names.first == currentName)
            #expect(Set(names).count == names.count)
            for name in names {
                #expect(defaults.bool(forKey: "NSStatusItem VisibleCC \(name)"))
                #expect(defaults.bool(forKey: "NSStatusItem Visible \(name)"))
            }
        }
    }

    @Test func helperEntrypointAndTargetUseTheSharedTestedContract() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VitrineMenuBarHelper/main.swift"),
            encoding: .utf8)
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8)
        let makefile = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Makefile"),
            encoding: .utf8)

        for required in [
            "MenuBarHelperConfiguration(arguments: arguments)",
            "MenuBarStatusItemVisibility.repair(",
            "MenuBarHelperContract.shouldRemainRunning(",
            "MenuBarHelperContract.isExpectedOwner(",
        ] {
            #expect(
                helperSource.contains(required),
                "the production helper must execute the tested contract: \(required)")
        }
        #expect(!helperSource.contains("arguments.count == 3"))
        #expect(project.contains("Vitrine/MenuBar/MenuBarHelperContract.swift"))
        #expect(makefile.contains("Vitrine VitrineCLI VitrineMenuBarHelper Tests UITests"))
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
        let controller = StatusItemController(
            environment: AppEnvironment(defaults: isolatedDefaults()),
            feedback: CaptureFeedbackPresenter(),
            navigation: .noOp)
        defer {
            if controller.isPanelShown {
                controller.togglePanel(at: anchor)
            }
        }

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
        let environment = AppEnvironment(defaults: isolatedDefaults())

        MenuBarDismissAction()()
        MenuBarContent(
            environment: environment,
            feedback: CaptureFeedbackPresenter(),
            navigation: .noOp
        ).dismiss()

        #expect(sideEffects == 0, "only the injected action may run")
        observed()
        #expect(sideEffects == 1)
    }

    @Test func navigationRoutesEveryDestinationAndEditorDocument() {
        var destinations: [MenuBarNavigation.Destination] = []
        var documents: [SnapshotConfig] = []
        var terminations = 0
        let navigation = MenuBarNavigation(
            present: { destinations.append($0) },
            loadPrimaryEditor: { documents.append($0) },
            terminate: { terminations += 1 })
        var config = SnapshotConfig()
        config.code = "let routed = true"

        for destination in MenuBarNavigation.Destination.allCases {
            navigation.show(destination)
        }
        navigation.loadIntoPrimaryEditor(config)
        navigation.terminateApplication()

        #expect(destinations == MenuBarNavigation.Destination.allCases)
        #expect(documents == [config])
        #expect(terminations == 1)
    }

    @Test func panelContainsNoWindowGlobalLookups() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Vitrine/MenuBar/MenuBarContent.swift"),
            encoding: .utf8)
        let code = sourceCodeWithoutLineComments(source)

        for forbiddenDependency in [
            "RecentsGalleryWindowController.shared",
            "EditorWindowController.shared",
            "WebSnapshotPresenter.show",
            "SocialCardWindowController.shared",
            "SettingsWindowManager.shared",
            "HelpWindowController.shared",
            "AboutPanel.present",
            "CaptureHUDController.shared",
            "ExportFeedback.present",
            "NSApp.terminate",
        ] {
            #expect(
                !code.contains(forbiddenDependency),
                "MenuBarContent must receive \(forbiddenDependency) as navigation")
        }
    }

    @Test func sourceGuardIgnoresLineComments() {
        let source = """
            navigation.show(.editor)
            // EditorWindowController.shared.show()
            navigation.show(.help) // HelpWindowController.shared.show()
            """

        let code = sourceCodeWithoutLineComments(source)

        #expect(code.contains("navigation.show(.editor)"))
        #expect(code.contains("navigation.show(.help)"))
        #expect(!code.contains("EditorWindowController.shared"))
        #expect(!code.contains("HelpWindowController.shared"))
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
