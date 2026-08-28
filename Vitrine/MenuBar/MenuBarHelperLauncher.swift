import AppKit
import Security

/// Owns the lifecycle of the minimal process that paints Vitrine's menu-bar item.
///
/// The helper executable lives inside the app bundle and inherits the app sandbox. A
/// separate process identity is required because Control Center can block every status
/// item owned by the main bundle while leaving the app running. The helper owns no user
/// data and self-exits when its exact containing Vitrine process disappears.
@MainActor
enum MenuBarHelperLauncher {
    static let executableName = MenuBarHelperContract.executableName

    private static var launchedProcess: Process?
    private static var sessionToken: String?

    /// Sandbox inheritance requires the parent and child to carry the same real
    /// signing team. Ad-hoc source builds have no team identifier, so launching the
    /// inherited-sandbox helper would trap in libsecinit before `main`; those builds
    /// deliberately keep the in-process status item instead.
    static var canLaunchInCurrentBundle: Bool {
        guard let executableURL else { return false }
        return signaturesPermitSandboxInheritance(
            appTeamIdentifier: signingTeamIdentifier(at: Bundle.main.bundleURL),
            helperTeamIdentifier: signingTeamIdentifier(at: executableURL))
    }

    static func signaturesPermitSandboxInheritance(
        appTeamIdentifier: String?, helperTeamIdentifier: String?
    ) -> Bool {
        guard
            let appTeamIdentifier,
            !appTeamIdentifier.isEmpty,
            let helperTeamIdentifier,
            !helperTeamIdentifier.isEmpty
        else { return false }
        return appTeamIdentifier == helperTeamIdentifier
    }

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

    private static func signingTeamIdentifier(at url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
                == errSecSuccess,
            let staticCode
        else { return nil }

        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &information) == errSecSuccess,
            let dictionary = information as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
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
