import Foundation

/// Static external URLs used by Vitrine.
///
/// Keeping these links in one Foundation-only place avoids duplicate URL literals
/// across AppKit/SwiftUI surfaces and keeps the constants reusable by future
/// platform-specific front ends.
enum VitrineLinks {
    nonisolated static let githubRepository = trustedHTTPSURL(
        "https://github.com/johnny4young/vitrine")
    nonisolated static let lemonSqueezyActivationEndpoint = trustedHTTPSURL(
        "https://api.lemonsqueezy.com/v1/licenses/activate")
    nonisolated static let lemonSqueezyDeactivationEndpoint = trustedHTTPSURL(
        "https://api.lemonsqueezy.com/v1/licenses/deactivate")
    nonisolated static let lemonSqueezyCheckout = trustedHTTPSURL(
        "https://johnny4young.lemonsqueezy.com/checkout/buy/"
            + "314e7d43-efa1-41be-a319-7474628e5185")

    /// Parses a credential-free absolute HTTPS URL without terminating the process.
    ///
    /// `URL(string:)` also accepts relative references, so a non-`nil` `URL` alone is not a
    /// sufficient trust boundary for provider endpoints. Invalid static configuration stays
    /// unavailable and lets each caller fail closed instead of crashing during type
    /// initialization.
    nonisolated static func trustedHTTPSURL(_ rawValue: String) -> URL? {
        guard let components = URLComponents(string: rawValue),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil
        else { return nil }
        return components.url
    }
}
