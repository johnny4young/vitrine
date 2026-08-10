import AppKit

/// Paint-only owner for Vitrine's menu-bar icon.
///
/// Control Center can keep the main app's status-item owner blocked even after AppKit
/// reports the item as visible. This minimal child has a separate process identity, so
/// it supplies a fresh paintable owner. It contains no product model and reads no user
/// content; clicking it sends only the main/helper process identifiers and the mouse
/// location back to the main app, which owns and presents the real panel.
@MainActor
private final class MenuBarHelperDelegate: NSObject, NSApplicationDelegate {
    private static let mainAppBundleID = "com.johnny4young.vitrine"
    private static let statusItemAutosaveName =
        MenuBarStatusItemVisibility.helperAutosaveName

    private let configuration: MenuBarHelperConfiguration
    private var statusItem: NSStatusItem?
    private var watchdog: Timer?

    init?(arguments: [String] = CommandLine.arguments) {
        guard let configuration = MenuBarHelperConfiguration(arguments: arguments) else {
            return nil
        }
        self.configuration = configuration
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard mainApp != nil else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Vitrine keeps a resident menu-bar helper")

        MenuBarStatusItemVisibility.repair(
            currentAutosaveName: Self.statusItemAutosaveName)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.statusItemAutosaveName
        item.behavior = []
        item.button?.image = menuBarImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Vitrine"
        item.button?.setAccessibilityLabel("Vitrine")
        item.button?.setAccessibilityIdentifier("menubar-status-item")
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.isVisible = true
        statusItem = item

        watchdog = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(checkOwner),
            userInfo: nil,
            repeats: true)
    }

    private func menuBarImage() -> NSImage {
        let image =
            NSImage(named: "vitrine-menubar")
            ?? NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "Vitrine")
            ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    @objc private func togglePanel() {
        guard mainApp != nil else {
            NSApp.terminate(nil)
            return
        }
        MenuBarAnchor(
            appProcessID: configuration.appProcessID,
            helperProcessID: ProcessInfo.processInfo.processIdentifier,
            sessionToken: configuration.sessionToken,
            clickLocation: NSEvent.mouseLocation
        ).post()
    }

    @objc private func checkOwner() {
        guard
            MenuBarHelperContract.shouldRemainRunning(
                statusItemVisible: statusItem?.isVisible == true,
                ownerExists: mainApp != nil)
        else {
            NSApp.terminate(nil)
            return
        }
    }

    /// A raw helper embedded in `Contents/MacOS` resolves `Bundle.main` to its
    /// containing Vitrine app. Match both bundle identity and exact bundle path so one
    /// installed copy can never keep another copy's helper alive.
    private var mainApp: NSRunningApplication? {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.mainAppBundleID
        ).first { application in
            MenuBarHelperContract.isExpectedOwner(
                candidateProcessID: application.processIdentifier,
                candidateExecutableURL: application.executableURL,
                candidateBundleURL: application.bundleURL,
                expectedProcessID: configuration.appProcessID,
                currentProcessID: currentProcessID,
                expectedBundleURL: Bundle.main.bundleURL)
        }
    }
}

guard let delegate = MenuBarHelperDelegate() else {
    exit(EXIT_FAILURE)
}
private let application = NSApplication.shared
application.delegate = delegate
application.run()
