import Foundation

/// Static external URLs used by Vitrine.
///
/// Keeping these links in one Foundation-only place avoids duplicate URL literals
/// across AppKit/SwiftUI surfaces and keeps the constants reusable by future
/// platform-specific front ends.
enum VitrineLinks {
    nonisolated static let githubRepository = requiredURL("https://github.com/johnny4young/vitrine")
    nonisolated static let lemonSqueezyActivationEndpoint = requiredURL(
        "https://api.lemonsqueezy.com/v1/licenses/activate")

    nonisolated private static func requiredURL(_ rawValue: String) -> URL {
        guard let url = URL(string: rawValue) else {
            preconditionFailure("Invalid static URL: \(rawValue)")
        }
        return url
    }
}
