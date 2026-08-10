import Foundation

/// Process-bound configuration accepted by the paint-only menu-bar helper.
///
/// The launcher always supplies a positive main-app process identifier and a fresh UUID.
/// Keeping that parser outside the executable entry point makes malformed invocation a
/// deterministic, tested failure instead of private top-level behavior.
struct MenuBarHelperConfiguration: Equatable, Sendable {
    static let maximumSessionTokenLength = 128

    let appProcessID: pid_t
    let sessionToken: String

    init?(arguments: [String]) {
        guard
            arguments.count == 3,
            let appProcessID = pid_t(arguments[1]),
            appProcessID > 0,
            !arguments[2].isEmpty,
            arguments[2].count <= Self.maximumSessionTokenLength,
            UUID(uuidString: arguments[2]) != nil
        else { return nil }

        self.appProcessID = appProcessID
        sessionToken = arguments[2]
    }
}

/// Pure owner/watchdog policy shared by the main app's tests and the helper process.
enum MenuBarHelperContract {
    static let executableName = "VitrineMenuBarHelper"

    /// The helper must follow the exact main-app process in its own containing bundle.
    /// Matching only the bundle identifier would let a second installed copy keep the
    /// wrong helper alive.
    static func isExpectedOwner(
        candidateProcessID: pid_t,
        candidateExecutableURL: URL?,
        candidateBundleURL: URL?,
        expectedProcessID: pid_t,
        currentProcessID: pid_t,
        expectedBundleURL: URL
    ) -> Bool {
        guard
            let candidateExecutableName = candidateExecutableURL?.lastPathComponent,
            let candidateBundleURL
        else { return false }

        return candidateProcessID != currentProcessID
            && candidateProcessID == expectedProcessID
            && candidateExecutableName != executableName
            && candidateBundleURL.standardizedFileURL == expectedBundleURL.standardizedFileURL
    }

    /// Losing either the painted status item or its exact owner ends the helper.
    static func shouldRemainRunning(statusItemVisible: Bool, ownerExists: Bool) -> Bool {
        statusItemVisible && ownerExists
    }
}

/// One source of truth for the status-item persistence identities repaired by both
/// processes. The current names differ intentionally, while the historical AppKit and
/// SwiftUI names must remain covered for upgrades from older builds.
enum MenuBarStatusItemVisibility {
    static let primaryAutosaveName = "VitrinePrimaryStatusItem"
    static let helperAutosaveName = "VitrineMenuBarHelperStatusItem"
    static let historicalAutosaveNames = ["Item-0", "Item-1", "Item-2"]

    static func repairedAutosaveNames(currentAutosaveName: String) -> [String] {
        [currentAutosaveName]
            + historicalAutosaveNames.filter { $0 != currentAutosaveName }
    }

    static func repair(
        in defaults: UserDefaults = .standard,
        currentAutosaveName: String
    ) {
        for autosaveName in repairedAutosaveNames(currentAutosaveName: currentAutosaveName) {
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(autosaveName)")
            defaults.set(true, forKey: "NSStatusItem Visible \(autosaveName)")
        }
        // AppKit reads these keys while its out-of-process host materializes the item.
        defaults.synchronize()
    }
}
