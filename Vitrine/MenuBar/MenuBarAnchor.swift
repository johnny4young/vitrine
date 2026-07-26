import AppKit

/// The content-free message sent when the external status-item owner is clicked.
///
/// The helper carries only process identifiers and the click location. It never reads
/// clipboard data, settings, recents, or rendered content; the main app keeps owning the
/// complete SwiftUI panel and validates that the message targets its exact process.
struct MenuBarAnchor: Equatable, Sendable {
    static let notificationName = Notification.Name(
        "com.johnny4young.vitrine.menu-bar.toggle-panel")

    let appProcessID: pid_t
    let helperProcessID: pid_t
    let sessionToken: String
    let clickLocation: CGPoint

    var encoded: String {
        [
            String(appProcessID),
            String(helperProcessID),
            sessionToken,
            String(Double(clickLocation.x)),
            String(Double(clickLocation.y)),
        ].joined(separator: "|")
    }

    init(
        appProcessID: pid_t,
        helperProcessID: pid_t,
        sessionToken: String,
        clickLocation: CGPoint
    ) {
        self.appProcessID = appProcessID
        self.helperProcessID = helperProcessID
        self.sessionToken = sessionToken
        self.clickLocation = clickLocation
    }

    init?(encoded: String) {
        let fields = encoded.split(separator: "|", omittingEmptySubsequences: false)
        guard
            fields.count == 5,
            let appProcessID = pid_t(fields[0]),
            let helperProcessID = pid_t(fields[1]),
            appProcessID > 0,
            helperProcessID > 0,
            !fields[2].isEmpty,
            fields[2].count <= 128,
            let x = Double(fields[3]),
            let y = Double(fields[4]),
            x.isFinite,
            y.isFinite
        else { return nil }

        self.init(
            appProcessID: appProcessID,
            helperProcessID: helperProcessID,
            sessionToken: String(fields[2]),
            clickLocation: CGPoint(x: x, y: y))
    }

    func post() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName,
            object: encoded,
            userInfo: nil,
            options: [.deliverImmediately])
    }
}
