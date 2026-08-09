import AppKit
import CoreServices
import KeyboardShortcuts
import OSLog

/// App lifecycle: configures the agent app and listens for the global hotkey.
///
/// The whole module defaults to `@MainActor` isolation (see `project.yml`), so this
/// delegate and the task it starts run on the main actor without extra annotations.
final class AppDelegate: NSObject, NSApplicationDelegate {
    enum HandoffRoute: Equatable {
        case edit
        case sharedSnapshot
    }

    private var hotkeyTask: Task<Void, Never>?
    private var menuBarPresenceTask: Task<Void, Never>?
    let environment: AppEnvironment
    let feedback: CaptureFeedbackPresenter
    let launchArguments: AppLaunchArgumentHandler
    let mainMenu: AppMenu

    override init() {
        let environment = AppEnvironment.shared
        let feedback = CaptureFeedbackPresenter.shared
        self.environment = environment
        self.feedback = feedback
        launchArguments = AppLaunchArgumentHandler(environment: environment)
        mainMenu = AppMenu(
            environment: environment,
            feedback: feedback,
            editorPresentation: .live)
        super.init()
    }

    init(
        environment: AppEnvironment,
        feedback: CaptureFeedbackPresenter,
        editorPresentation: EditorPresentation
    ) {
        self.environment = environment
        self.feedback = feedback
        launchArguments = AppLaunchArgumentHandler(environment: environment)
        mainMenu = AppMenu(
            environment: environment,
            feedback: feedback,
            editorPresentation: editorPresentation)
        super.init()
    }

    enum MenuBarOwner: Equatable {
        case disabled
        case inProcess
        case helper
    }

    /// Enforce a single running instance. A menu-bar agent must never stack a second
    /// status item, but launching the same bundle id from a different path — several
    /// Xcode DerivedData copies, or `open`-ing more than one built `.app` — starts a
    /// second process with the same identifier. If another Vitrine is already running
    /// when this one launches, hand activation back to it and exit *before*
    /// `StatusItemController` installs a duplicate icon. UI tests are unaffected:
    /// `XCUIApplication.launch()` terminates any prior instance before launching, so no
    /// other instance is ever present here under test.
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Handle `vitrine://edit` handoffs from the CLI (`--edit`). Register before the
        // single-instance guard and the SwiftUI scene so a URL that *cold-launches* the
        // app is still delivered once the AppleEvent queue drains. When an instance is
        // already running, the OS routes the open to it instead of spawning a new one.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        // Never enforce single-instance under tests. The *unit*-test host launches this
        // app to host XCTest (`XCTestConfigurationFilePath` is set) even while a developer
        // instance is open; exiting here aborts the run with "test runner exited before
        // establishing connection". The *UI*-test host instead sets
        // `VITRINE_USER_DEFAULTS_SUITE` (also used for test isolation). Either signal
        // means "do not enforce".
        guard Self.shouldEnforceSingleInstance(ProcessInfo.processInfo.environment) else { return }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter {
                $0 != .current
                    && $0.executableURL?.lastPathComponent
                        != MenuBarHelperLauncher.executableName
            }
        if let existing = others.first {
            existing.activate()
            exit(0)
        }
    }

    /// Whether to enforce the single-instance guard for a launch with this environment.
    /// Returns `false` under tests — the unit-test host sets `XCTestConfigurationFilePath`
    /// and the UI-test host sets `VITRINE_USER_DEFAULTS_SUITE` — so a test run is never
    /// killed by a developer instance that happens to be open. Pure + injectable so the
    /// rule is unit-testable.
    static func shouldEnforceSingleInstance(_ environment: [String: String]) -> Bool {
        environment["VITRINE_USER_DEFAULTS_SUITE"] == nil
            && environment["XCTestConfigurationFilePath"] == nil
    }

    /// Chooses the status-item owner without leaking helper processes into tests.
    /// Unit tests exercise `StatusItemController` explicitly, while UI tests keep the
    /// item in-process so XCUIAutomation can reach it through the launched app.
    static func menuBarOwner(for environment: [String: String]) -> MenuBarOwner {
        if environment["XCTestConfigurationFilePath"] != nil { return .disabled }
        // Manual runtime QA can combine an isolated defaults suite with the real helper
        // boundary, producing review evidence without reading a developer's recents.
        if environment["VITRINE_FORCE_MENU_BAR_HELPER"] == "1" { return .helper }
        if environment["VITRINE_USER_DEFAULTS_SUITE"] != nil { return .inProcess }
        return .helper
    }

    /// GetURL AppleEvent entry point: pulls the `vitrine://…` string out of the event
    /// and routes it to `openHandoff`.
    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?
                .stringValue,
            let url = URL(string: urlString)
        else { return }
        openHandoff(url)
    }

    /// Classifies a Vitrine URL using the case-insensitive scheme and host rules defined
    /// by URL standards. Keeping this pure prevents the AppleEvent route from drifting
    /// from the link decoders.
    static func handoffRoute(for url: URL) -> HandoffRoute? {
        guard url.scheme?.lowercased() == SnapshotShareLink.scheme else { return nil }
        switch url.host?.lowercased() {
        case EditorHandoff.editHost: return .edit
        case SnapshotShareLink.host: return .sharedSnapshot
        default: return nil
        }
    }

    /// Routes an incoming `vitrine://…` URL by host. Any unrecognized URL is ignored.
    func openHandoff(_ url: URL) {
        switch Self.handoffRoute(for: url) {
        case .edit: openEditHandoff(url)
        case .sharedSnapshot: openSharedSnapshot(url)
        case nil: break
        }
    }

    /// Seeds the editor from a `vitrine://edit` handoff (the CLI's `--edit`): reads the
    /// staged content and optional language hint, then loads it into the primary editor
    /// replacing that window's document like quick capture and the Open-Code App
    /// Intent do, seeded on the user's current style. A no-op for an empty payload.
    private func openEditHandoff(_ url: URL) {
        guard let handoff = EditorHandoff.consume(url: url) else { return }
        var config = environment.appSettings.config
        config.code = handoff.content
        if let language = handoff.language { config.language = language }
        EditorWindowController.shared.loadIntoPrimary(config)
        NSApp.activate(ignoringOtherApps: true)
        Log.app.notice("Opened a CLI --edit handoff in the editor")
    }

    /// Opens a shared-snapshot link (`vitrine://open`): decodes the untrusted
    /// payload into a `SharedSnapshot`, applies it onto a fresh config so the receiver
    /// sees exactly the sender's styled code (never a leftover foreground image), and
    /// loads it into the primary editor. A malformed or unsupported link is a silent
    /// no-op — the decoder already refused it — so a hostile URL can't disturb the
    /// current document.
    private func openSharedSnapshot(_ url: URL) {
        guard let snapshot = try? SnapshotShareLink.snapshot(from: url) else { return }
        var config = SnapshotConfig()
        snapshot.apply(to: &config)
        EditorWindowController.shared.loadIntoPrimary(config)
        NSApp.activate(ignoringOtherApps: true)
        Log.app.notice("Opened a shared snapshot link in the editor")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("Vitrine launched")
        // Agent app — no Dock icon (also declared via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        // Collect persistent per-window suites created by earlier releases. Current
        // sessions are process-local, but existing installs may still carry old files;
        // anything past the concurrent-instance age guard is safe to migrate away.
        AppSettings.sweepStaleEditorSessionSuites(
            preferencesDirectory: AppSettings.preferencesDirectory)

        // This is the app's only persistent affordance. A minimal child process owns the
        // icon in production because Control Center can block the main bundle's status
        // items while leaving the app alive. The main app still owns the real panel and
        // every command; the helper sends only a click location back here.
        establishMenuBarPresence()

        // Install the application main menu. An agent app with no `WindowGroup` gets no
        // designed menu bar from SwiftUI; assigning one
        // here gives the editor and settings windows a complete, keyboard-accessible
        // menu bar (App ▸, File ▸, Edit ▸, View ▸, Window ▸, Help ▸). SwiftUI's scene
        // bring-up overwrites this menu with its own default after this method
        // returns, so `applicationWillUpdate(_:)` below re-asserts it.
        mainMenu.install()

        // Global hotkey: consume the key-up event stream on the main actor
        // and dispatch to the user-chosen action.
        hotkeyTask = Task {
            for await _ in KeyboardShortcuts.events(.keyUp, for: .quickCapture) {
                handleHotkey()
            }
        }

        // Resolve the PRO entitlement at launch and — on the App Store build — observe
        // out-of-band StoreKit updates, so a refund or a purchase made on another device
        // re-locks/unlocks PRO without a relaunch.
        environment.entitlements.startLiveUpdates()

        // First-run surfaces on a normal launch: onboarding owns the
        // first launch; once it has been seen, What's New surfaces on a version
        // upgrade — never both. Skipped when a dev launch hook already opened a window
        // so the manual/UI-test surfaces above are not pre-empted or stacked over.
        if !launchArguments.handle() {
            let settings = environment.appSettings
            if !WelcomeWindowController.shared.presentIfFirstRun(settings: settings) {
                WhatsNewWindowController.shared.presentIfNewVersion(settings: settings)
            }
        }

        // Pay the syntax highlighter's one-time cold start now, off the render path, so
        // a user whose first interaction is a ⇧⌘S quick capture doesn't eat the
        // JavaScriptCore + theme-CSS warm-up inside the "instant" gesture. Low priority
        // so it never contends with the menu bar coming up or a hotkey already firing.
        Task(priority: .utility) { HighlightManager.shared.prewarm() }
    }

    private func handleHotkey() {
        let action = environment.appSettings.hotkeyAction
        Log.app.info("Global hotkey fired (\(action.rawValue, privacy: .public))")
        switch action {
        case .quickCapture:
            QuickCapture.perform(environment: environment, feedback: feedback)
        case .openEditor:
            EditorWindowController.shared.show()
        }
    }

    // MARK: - Menu-bar presence

    private func establishMenuBarPresence() {
        switch Self.menuBarOwner(for: ProcessInfo.processInfo.environment) {
        case .disabled:
            return
        case .inProcess:
            StatusItemController.shared.attach()
        case .helper:
            startMenuBarCommandChannel()
            menuBarPresenceTask?.cancel()
            menuBarPresenceTask = Task {
                while !Task.isCancelled {
                    if !MenuBarHelperLauncher.isHelperRunning() {
                        guard MenuBarHelperLauncher.launch() else {
                            StatusItemController.shared.attach()
                            do {
                                try await Task.sleep(for: .seconds(2))
                            } catch {
                                return
                            }
                            continue
                        }

                        // Process.run() returns before NSWorkspace registers the child.
                        // Give that registration a bounded window before retaining the
                        // in-process fallback.
                        for _ in 0..<20 where !MenuBarHelperLauncher.isHelperRunning() {
                            do {
                                try await Task.sleep(for: .milliseconds(100))
                            } catch {
                                return
                            }
                        }
                    }

                    if MenuBarHelperLauncher.isHelperRunning() {
                        StatusItemController.shared.detach()
                    } else {
                        StatusItemController.shared.attach()
                    }

                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                }
            }
        }
    }

    private func startMenuBarCommandChannel() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveMenuBarToggle(_:)),
            name: MenuBarAnchor.notificationName,
            object: nil,
            suspensionBehavior: .deliverImmediately)
    }

    @objc private func receiveMenuBarToggle(_ notification: Notification) {
        guard
            let encoded = notification.object as? String,
            let anchor = MenuBarAnchor(encoded: encoded),
            MenuBarHelperLauncher.validates(anchor)
        else { return }

        StatusItemController.shared.togglePanel(
            at: anchor.clickLocation,
            helperProcessID: anchor.helperProcessID)
    }

    /// SwiftUI's scene bring-up installs its default main menu shortly after
    /// `applicationDidFinishLaunching` — by replacing the installed menu's items in
    /// place — wiping the designed menu installed above (File and Edit vanish from the
    /// menu bar, and main-menu key equivalents like ⌘E and ⌘S go dead). Re-assert the
    /// AppKit menu whenever it has been taken over; the pointer checks inside keep this
    /// effectively free on this hot every-event path.
    func applicationWillUpdate(_ notification: Notification) {
        mainMenu.reinstallIfDisplaced()
        StatusItemController.shared.restoreVisibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.notice("Vitrine terminating")
        // The primary editor session survives window close by design, so clean shutdown
        // is its normal opportunity to clear ephemeral draft objects promptly.
        EditorWindowController.shared.discardAllSessions()
        hotkeyTask?.cancel()
        menuBarPresenceTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(
            self, name: MenuBarAnchor.notificationName, object: nil)
        MenuBarHelperLauncher.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
