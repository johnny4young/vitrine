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
    static let shared = StatusItemController()

    /// A deterministic identity lets the app repair the exact persistence keys AppKit
    /// applies while Control Center hosts the item. The historical names cover builds
    /// that let AppKit or SwiftUI choose an identity.
    static let autosaveName = "VitrinePrimaryStatusItem"
    static let repairedAutosaveNames = [autosaveName, "Item-0", "Item-1", "Item-2"]

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
    private var visibilityRepairTask: Task<Void, Never>?
    private let visibilityRepairDelays: [Duration]

    init(visibilityRepairDelays: [Duration] = defaultVisibilityRepairDelays) {
        self.visibilityRepairDelays = visibilityRepairDelays
        super.init()
    }

    /// Whether the item is currently installed in the menu bar.
    var isAttached: Bool { statusItem != nil }

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
        popover?.performClose(nil)
        popover = nil
        discardExternalAnchor()
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
    func togglePanel(at clickLocation: CGPoint) {
        guard Self.isValidAnchorLocation(clickLocation) else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

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

        togglePanel(relativeTo: anchor)
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

    private func togglePanel(relativeTo anchor: NSView) {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        showPanel(relativeTo: anchor)
    }

    private func showPanel(relativeTo anchor: NSView) {
        let popover = popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        // The panel takes keyboard focus so its controls are reachable without a click;
        // an external-helper click activates that process rather than the main app.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        // Transient: clicking outside or switching apps closes the panel, matching how a
        // menu behaves and how the `MenuBarExtra(.window)` surface used to.
        popover.behavior = .transient
        popover.delegate = self
        let content = MenuBarContent(
            dismiss: MenuBarDismissAction { [weak self] in
                self?.popover?.performClose(nil)
            }
        )
        .environment(AppSettings.shared)
        .environment(RecentsStore.shared)
        .environment(CaptureFeedbackPresenter.shared)
        popover.contentViewController = NSHostingController(rootView: content)
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        discardExternalAnchor()
    }

    private func discardExternalAnchor() {
        externalAnchorWindow?.orderOut(nil)
        externalAnchorWindow = nil
    }
}
