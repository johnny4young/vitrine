import Foundation

/// A post-launch, per-launch authenticated command used only by menu-bar UI tests.
///
/// XCTest can occasionally see an in-process status item on a secondary display but
/// refuse to click its negative-coordinate accessibility frame. The production click
/// remains the primary UI-test path; this channel provides a deterministic fallback
/// only when the app was explicitly launched with a private random test token.
enum MenuBarUITestControl {
    static let launchArgumentPrefix = "--menu-panel-ui-test-control="
    static let notificationName = Notification.Name(
        "com.johnny4young.vitrine.ui-test.open-menu-panel")

    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        token(arguments: arguments) != nil
    }

    static func accepts(
        _ notification: Notification,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        guard let expectedToken = token(arguments: arguments) else {
            return false
        }
        return notification.object as? String == expectedToken
    }

    private static func token(arguments: [String]) -> String? {
        guard
            let argument = arguments.first(where: { $0.hasPrefix(launchArgumentPrefix) }),
            let token = argument.split(separator: "=", maxSplits: 1).last.map(String.init),
            UUID(uuidString: token) != nil
        else { return nil }
        return token
    }
}
