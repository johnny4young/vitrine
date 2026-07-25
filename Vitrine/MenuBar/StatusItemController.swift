import AppKit
import SwiftUI

/// Owns Vitrine's menu-bar status item and the panel it presents.
///
/// SwiftUI's `MenuBarExtra` is deliberately **not** used for this. On macOS 26 the item
/// that scene vends is hosted by Control Center, and a *persisted* hidden state for it
/// (`NSStatusItem VisibleCC <autosave>` = `0`, written when the icon is Command-dragged
/// out of the menu bar or hidden by a menu-bar manager) is re-applied while AppKit
/// materializes the button. AppKit then removes the item, logging
/// `StatusBar: 0 terminating on removal` — and because the `MenuBarExtra` scene was this
/// agent's only scene, that removal terminated the whole process about 60 ms after
/// launch. The symptom is brutal to diagnose and impossible to recover from in the UI:
/// the app exits 0 with no crash report, and there is no icon left to un-hide. It also
/// killed the unit-test host, which launches this same bundle.
///
/// Owning a plain `NSStatusItem` fixes it three ways: the item is created with **no
/// autosave name**, so no menu-bar customization state is persisted for it to be trapped
/// by; `behavior` is left at its default, so it cannot be dragged out of the menu bar at
/// all; and any state a previous build already persisted is repaired before the item is
/// created and re-asserted after its button materializes.
@MainActor
final class StatusItemController: NSObject {
    /// The app's single status item. A second one would stack a duplicate icon.
    static let shared = StatusItemController()

    /// Autosave names to repair. SwiftUI named its item automatically, and `Item-0` is
    /// what it picked in practice; the neighbours cover a different pick by an older or
    /// newer build, since a stale `0` under any of them re-creates the trap.
    static let repairedAutosaveNames = ["Item-0", "Item-1", "Item-2"]

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// Whether the item is currently installed in the menu bar.
    var isAttached: Bool { statusItem != nil }

    /// Installs the status item. Idempotent: a second call is a no-op, so a repeated
    /// launch hook can never stack two icons.
    func attach() {
        guard statusItem == nil else { return }

        Self.repairVisibilityDefaults()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // `behavior` stays at its default (no `.removalAllowed`): removing this item is
        // exactly what used to end the process, so it must not be removable by a drag.
        item.button?.image = Self.menuBarImage()
        // "Vitrine" is the verbatim brand wordmark, like the other brand strings that
        // bypass the String Catalog.
        item.button?.toolTip = "Vitrine"
        item.button?.setAccessibilityIdentifier("menubar-status-item")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        // AppKit can apply its own chosen visibility autosave state while materializing
        // the button, so assert visibility once *after* that first setup rather than
        // trusting the pre-creation repair alone.
        item.isVisible = true
    }

    /// Removes the item. Used by tests; production keeps it for the process's lifetime.
    func detach() {
        popover?.performClose(nil)
        popover = nil
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
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
    }

    // MARK: - Panel

    /// Toggles the panel, so clicking the icon while it is open closes it — the same
    /// behaviour a native menu has.
    @objc private func togglePanel() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let button = statusItem?.button else { return }
        let popover = popover ?? makePopover()
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // The panel takes keyboard focus so its controls are reachable without a click;
        // the app is an accessory, so it gets no activation from the click alone.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        // Transient: clicking outside or switching apps closes the panel, matching how a
        // menu behaves and how the `MenuBarExtra(.window)` surface used to.
        popover.behavior = .transient
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
}
