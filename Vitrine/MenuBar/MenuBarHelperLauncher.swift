import AppKit

/// Owns the lifecycle of the minimal process that paints Vitrine's menu-bar item.
///
/// The helper executable lives inside the app bundle and inherits the app sandbox. A
/// separate process identity is required because Control Center can block every status
/// item owned by the main bundle while leaving the app running. The helper owns no user
/// data and self-exits when its exact containing Vitrine process disappears.
@MainActor
enum MenuBarHelperLauncher {
    static let executableName = "VitrineMenuBarHelper"

    private static var launchedProcess: Process?
    private static var sessionToken: String?

    @discardableResult
    static func launch() -> Bool {
        if launchedProcess?.isRunning == true { return true }
        guard let executableURL else { return false }

        stop()

        let process = Process()
        process.executableURL = executableURL
        let token = UUID().uuidString
        process.arguments = [
            String(ProcessInfo.processInfo.processIdentifier),
            token,
        ]
        do {
            try process.run()
            launchedProcess = process
            sessionToken = token
            return true
        } catch {
            launchedProcess = nil
            sessionToken = nil
            Log.app.error(
                "Could not launch the menu-bar helper: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func stop() {
        if launchedProcess?.isRunning == true { launchedProcess?.terminate() }
        launchedProcess = nil
        sessionToken = nil
    }

    static func isHelperRunning() -> Bool {
        guard
            let process = launchedProcess,
            process.isRunning,
            runningHelpers.contains(where: { $0.processIdentifier == process.processIdentifier })
        else { return false }
        return true
    }

    static func validates(_ anchor: MenuBarAnchor) -> Bool {
        guard
            anchor.appProcessID == ProcessInfo.processInfo.processIdentifier,
            anchor.sessionToken == sessionToken,
            anchor.helperProcessID == launchedProcess?.processIdentifier
        else { return false }
        return runningHelpers.contains { $0.processIdentifier == anchor.helperProcessID }
    }

    private static var executableURL: URL? {
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            return nil
        }
        let url = directory.appendingPathComponent(executableName, isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private static var runningHelpers: [NSRunningApplication] {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { application in
            application.processIdentifier != currentProcessID
                && application.executableURL?.lastPathComponent == executableName
                && application.bundleURL?.standardizedFileURL
                    == Bundle.main.bundleURL.standardizedFileURL
        }
    }
}
