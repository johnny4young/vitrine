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
    private static let statusItemAutosaveName = "VitrineMenuBarHelperStatusItem"

    private let appProcessID: pid_t
    private let sessionToken: String
    private var statusItem: NSStatusItem?
    private var watchdog: Timer?

    init?(arguments: [String] = CommandLine.arguments) {
        guard
            arguments.count == 3,
            let appProcessID = pid_t(arguments[1]),
            appProcessID > 0,
            !arguments[2].isEmpty,
            arguments[2].count <= 128
        else { return nil }

        self.appProcessID = appProcessID
        sessionToken = arguments[2]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard mainApp != nil else {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Vitrine keeps a resident menu-bar helper")

        repairHistoricalVisibility()

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

    private func repairHistoricalVisibility() {
        let defaults = UserDefaults.standard
        for name in [Self.statusItemAutosaveName, "Item-0", "Item-1", "Item-2"] {
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(name)")
            defaults.set(true, forKey: "NSStatusItem Visible \(name)")
        }
        defaults.synchronize()
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
            appProcessID: appProcessID,
            helperProcessID: ProcessInfo.processInfo.processIdentifier,
            sessionToken: sessionToken,
            clickLocation: NSEvent.mouseLocation
        ).post()
    }

    @objc private func checkOwner() {
        guard statusItem?.isVisible == true, mainApp != nil else {
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
            application.processIdentifier != currentProcessID
                && application.processIdentifier == appProcessID
                && application.executableURL?.lastPathComponent != "VitrineMenuBarHelper"
                && application.bundleURL?.standardizedFileURL
                    == Bundle.main.bundleURL.standardizedFileURL
        }
    }
}

guard let delegate = MenuBarHelperDelegate() else {
    exit(EXIT_FAILURE)
}
private let application = NSApplication.shared
application.delegate = delegate
application.run()
