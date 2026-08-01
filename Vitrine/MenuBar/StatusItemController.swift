import AppKit
import SwiftUI

/// Owns Vitrine's menu-bar panel and the in-process status-item fallback.
///
/// SwiftUI's `MenuBarExtra` is deliberately **not** used. On macOS 26 its Control
/// Center-hosted item can be removed from the bar and terminate a windowless agent. A
/// plain in-process `NSStatusItem` fixed that termination path, but Control Center can
/// also keep every status item owned by the main bundle in its blocked list: AppKit
/// reports the item visible while no window is painted and the app remains unreachable.
///
/// Production therefore lets `VitrineMenuBarHelper` own the painted icon with a fresh
/// process identity. A click carries only process identifiers and the mouse location
/// back here; this controller anchors the real, model-backed SwiftUI panel at that point.
/// The in-process item remains for UI tests and as a launch fallback. It has a stable
/// identity, fixed width, no removal behavior, repaired defaults, and a bounded
/// post-materialization visibility repair.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    /// The app's single status item. A second one would stack a duplicate icon.
    static let shared = StatusItemController(
        environment: .shared,
        feedback: .shared,
        navigation: .live)

    /// A deterministic identity lets the app repair the exact persistence keys AppKit
    /// applies while Control Center hosts the item. The historical names cover builds
    /// that let AppKit or SwiftUI choose an identity.
    static let autosaveName = "VitrinePrimaryStatusItem"
    static let repairedAutosaveNames = [autosaveName, "Item-0", "Item-1", "Item-2"]
    /// Vitrine owns dismissal because the helper's opening click comes from another
    /// process. Explicit event monitors reproduce native outside-interaction behavior
    /// without treating that cross-process handoff as an immediate dismissal.
    static let popoverBehavior: NSPopover.Behavior = .applicationDefined

    /// The initial host transition completes asynchronously. Keep the repair bounded:
    /// the later pass lands after the transition without turning visibility into a
    /// permanent polling loop.
    private static let defaultVisibilityRepairDelays: [Duration] = [
        .milliseconds(100),
        .milliseconds(500),
    ]

    private(set) var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var externalAnchorWindow: NSWindow?
    private var localPointerMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalPointerMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var helperProcessID: pid_t?
    private var visibilityRepairTask: Task<Void, Never>?
    /// The data graph supplied to the panel and every quick-capture action it starts.
    let environment: AppEnvironment
    /// The UI lifecycle presenter retained alongside the panel so transient and inline
    /// feedback share one state owner.
    let feedback: CaptureFeedbackPresenter
    /// The window-routing operations supplied to the panel.
    let navigation: MenuBarNavigation
    private let visibilityRepairDelays: [Duration]

    init(
        environment: AppEnvironment,
        feedback: CaptureFeedbackPresenter,
        navigation: MenuBarNavigation,
        visibilityRepairDelays: [Duration] = defaultVisibilityRepairDelays
    ) {
        self.environment = environment
        self.feedback = feedback
        self.navigation = navigation
        self.visibilityRepairDelays = visibilityRepairDelays
        super.init()
    }

    /// Whether the item is currently installed in the menu bar.
    var isAttached: Bool { statusItem != nil }

    /// Whether the model-backed panel is currently presented. Kept independent from
    /// fallback-item ownership because the helper monitor may remove that item while
    /// the external helper's panel remains open.
    var isPanelShown: Bool { popover?.isShown == true }

    /// Whether the helper-owned anchor is configured to survive the main app becoming
    /// inactive during the cross-process click handoff.
    var externalAnchorSurvivesDeactivation: Bool {
        externalAnchorWindow?.hidesOnDeactivate == false
    }

    /// Installs the status item. Idempotent: a second call is a no-op, so a repeated
    /// launch hook can never stack two icons.
    func attach() {
        guard statusItem == nil else { return }

        Self.repairVisibilityDefaults()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.autosaveName
        // Removing this item used to end the process, so make the no-removal contract
        // explicit instead of depending on AppKit's default option set.
        item.behavior = []
        item.button?.image = Self.menuBarImage()
        item.button?.imagePosition = .imageOnly
        // "Vitrine" is the verbatim brand wordmark, like the other brand strings that
        // bypass the String Catalog.
        item.button?.toolTip = "Vitrine"
        item.button?.setAccessibilityIdentifier("menubar-status-item")
        item.button?.target = self
        item.button?.action = #selector(toggleStatusItemPanel)
        statusItem = item

        restoreVisibility()
        scheduleVisibilityRepair()
    }

    /// Removes the in-process fallback once the external owner is confirmed.
    func detach() {
        visibilityRepairTask?.cancel()
        visibilityRepairTask = nil
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    /// Reasserts the item when a lifecycle update observes AppKit hiding it. The method
    /// is intentionally idempotent so launch-time repair and application updates share
    /// one path without creating another item.
    func restoreVisibilityIfNeeded() {
        guard let statusItem, !statusItem.isVisible else { return }
        restoreVisibility()
    }

    /// Restores both the persisted and live state. Reapplying the fixed width nudges the
    /// host to publish a non-zero presentation even when visibility already reads true.
    private func restoreVisibility() {
        guard let statusItem else { return }
        Self.repairVisibilityDefaults()
        statusItem.length = NSStatusItem.squareLength
        statusItem.isVisible = true
    }

    /// Runs only during attachment. A synchronous `isVisible = true` is too early:
    /// Control Center can apply its hosted scene state after `attach()` returns.
    private func scheduleVisibilityRepair() {
        visibilityRepairTask?.cancel()
        visibilityRepairTask = Task { [weak self] in
            guard let self else { return }
            for delay in visibilityRepairDelays {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, statusItem != nil else { return }
                restoreVisibility()
            }
        }
    }

    /// The status-bar glyph: the real Vitrine logo (viewfinder + code chevrons), shipped
    /// as a monochrome template image set so macOS tints it for light/dark bars and
    /// selection — not the generic `camera.viewfinder` SF Symbol. See
    /// `assets/brand/vitrine-menubar-*` in the design system.
    private static func menuBarImage() -> NSImage? {
        let image = NSImage(named: "vitrine-menubar")
        image?.isTemplate = true
        return image
    }

    /// Clears a persisted "hidden" state for the menu-bar item before it exists.
    ///
    /// Written in-process, and before the item is created, on purpose: an external
    /// `defaults write` does not survive, because AppKit re-applies its own autosave
    /// state while materializing the button and overwrites it.
    /// Takes the store so a test can assert the repair against an isolated suite instead
    /// of the running app's own defaults.
    static func repairVisibilityDefaults(in defaults: UserDefaults = .standard) {
        for autosaveName in repairedAutosaveNames {
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(autosaveName)")
            defaults.set(true, forKey: "NSStatusItem Visible \(autosaveName)")
        }
        // AppKit reads these keys while attaching the out-of-process Control Center
        // host, so flush the repair before that host finishes materializing the item.
        defaults.synchronize()
    }

    // MARK: - Panel

    /// Toggles the panel, so clicking the icon while it is open closes it — the same
    /// behaviour a native menu has.
    @objc private func toggleStatusItemPanel() {
        guard let button = statusItem?.button else { return }
        togglePanel(relativeTo: button)
    }

    /// Presents the main app's panel under a click received by the external icon owner.
    /// The invisible anchor is process-local and contains no user content.
    func togglePanel(at clickLocation: CGPoint, helperProcessID: pid_t? = nil) {
        guard Self.isValidAnchorLocation(clickLocation) else { return }
        if let popover, popover.isShown {
            dismissPanel()
            return
        }
        self.helperProcessID = helperProcessID

        let side: CGFloat = 24
        let frame = NSRect(
            x: clickLocation.x - side / 2,
            y: clickLocation.y - side / 2,
            width: side,
            height: side)
        let window = NSPanel(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // NSPanel hides on app deactivation by default. The status-item click starts in
        // the helper process, so an activation transition must not hide the positioning
        // window and take its attached popover with it.
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        let anchor = NSView(frame: NSRect(origin: .zero, size: frame.size))
        window.contentView = anchor
        window.orderFrontRegardless()
        externalAnchorWindow = window

        showPanel(relativeTo: anchor)
    }

    /// Opens the real panel at a stable on-screen anchor for development and UI automation.
    /// This avoids depending on status-item accessibility geometry without changing the
    /// production helper or click path.
    func showPanelForAutomation() {
        guard !isPanelShown, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        togglePanel(at: CGPoint(x: frame.maxX - 24, y: frame.maxY - 12))
    }

    /// Rejects malformed or spoofed positions before creating a process-local panel.
    /// Real helper clicks always land inside one of the current display frames.
    static func isValidAnchorLocation(
        _ location: CGPoint,
        screenFrames: [CGRect] = NSScreen.screens.map(\.frame)
    ) -> Bool {
        location.x.isFinite
            && location.y.isFinite
            && screenFrames.contains(where: { $0.contains(location) })
    }

    /// Workspace notifications include the activated process. The main app and its icon
    /// helper are part of one interaction surface; every other process represents a
    /// genuine focus change.
    static func shouldDismissForActivatedProcess(
        _ processID: pid_t,
        appProcessID: pid_t = ProcessInfo.processInfo.processIdentifier,
        helperProcessID: pid_t?
    ) -> Bool {
        processID != appProcessID && processID != helperProcessID
    }

    /// A second click on the helper icon is handled by the regular toggle command. Every
    /// other global pointer event is an outside click and dismisses the panel.
    static func shouldDismissForGlobalPointer(
        at location: CGPoint,
        anchorFrame: CGRect?
    ) -> Bool {
        guard let anchorFrame else { return true }
        return !anchorFrame.insetBy(dx: -4, dy: -4).contains(location)
    }

    /// Escape is the system cancel command. Monitor its hardware-independent AppKit
    /// key code as a fallback for panels whose hosted SwiftUI view has no focused
    /// control to receive `onExitCommand`.
    static func shouldDismissForKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == 53
    }

    private func togglePanel(relativeTo anchor: NSView) {
        if let popover, popover.isShown {
            dismissPanel()
            return
        }
        helperProcessID = nil
        showPanel(relativeTo: anchor)
    }

    private func showPanel(relativeTo anchor: NSView) {
        let popover = popover ?? makePopover()
        self.popover = popover
        // The external click activates the helper. Complete the activation handoff before
        // presentation so AppKit cannot treat it as a reason to close the new panel.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        // The panel takes keyboard focus so its controls are reachable without a click.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = Self.popoverBehavior
        popover.delegate = self
        let content = MenuBarContent(
            environment: environment,
            feedback: feedback,
            navigation: navigation,
            dismiss: MenuBarDismissAction { [weak self] in
                self?.dismissPanel()
            }
        )
        popover.contentViewController = NSHostingController(rootView: content)
        return popover
    }

    func popoverDidShow(_ notification: Notification) {
        installDismissalObservers()
    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissalObservers()
        helperProcessID = nil
        discardExternalAnchor()
    }

    private func installDismissalObservers() {
        removeDismissalObservers()

        localPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            let eventWindow = event.window
            let popoverWindow = popover?.contentViewController?.view.window
            let statusItemWindow = statusItem?.button?.window
            if eventWindow !== popoverWindow && eventWindow !== statusItemWindow {
                dismissPanel()
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, Self.shouldDismissForKeyCode(event.keyCode) else {
                return event
            }
            dismissPanel()
            return nil
        }

        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard
                    let self,
                    Self.shouldDismissForGlobalPointer(
                        at: location,
                        anchorFrame: externalAnchorWindow?.frame)
                else { return }
                dismissPanel()
            }
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let processID =
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication)?.processIdentifier
            else { return }
            Task { @MainActor [weak self] in
                guard
                    let self,
                    Self.shouldDismissForActivatedProcess(
                        processID, helperProcessID: helperProcessID)
                else { return }
                dismissPanel()
            }
        }
    }

    /// All close paths converge here so SwiftUI commands, pointer monitors, workspace
    /// activation, and icon toggles receive the same delegate-driven cleanup.
    private func dismissPanel() {
        popover?.close()
    }

    private func removeDismissalObservers() {
        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
            self.localPointerMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
            self.globalPointerMonitor = nil
        }
        if let appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
    }

    private func discardExternalAnchor() {
        externalAnchorWindow?.orderOut(nil)
        externalAnchorWindow = nil
    }
}
