import Foundation
import UserNotifications

/// Surfaces quick-capture outcomes as non-intrusive banners (CS-016).
enum Notifier {
    /// The user-facing message for an outcome (pure and unit-testable).
    static func message(for outcome: QuickCapture.Outcome) -> String? {
        switch outcome {
        case .copied: "Image copied to the clipboard"
        case .rendered: "Image rendered"
        case .url: "That looks like a URL — screenshot capture is coming soon"
        case .empty: "Clipboard is empty — copy some code first"
        }
    }

    /// Posts a banner for `outcome`. No-op when notifications are unauthorized.
    static func notify(_ outcome: QuickCapture.Outcome) {
        guard let body = message(for: outcome) else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Vitrine"
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}
