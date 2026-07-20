import Foundation

/// Builds the web compose ("intent") URLs behind the share sheet's Post-to targets.
/// Pure URL construction — opening the browser and staging the image on
/// the clipboard is the caller's job — so the encoding is unit-testable.
///
/// The web intents cannot attach an image, so the flow is: copy the rendered PNG to
/// the clipboard, open the compose page with the text prefilled, and tell the user to
/// paste — one paste away from posting, with nothing sent anywhere by Vitrine itself.
enum SocialComposer {
    /// A network the share sheet offers a compose target for. Mastodon is deliberately
    /// absent: its compose URL is per-instance, so there is no one URL to build.
    enum Network: String, CaseIterable, Identifiable {
        case x
        case linkedIn
        case bluesky

        var id: String { rawValue }

        /// The share-sheet item title.
        var title: String {
            switch self {
            case .x: String(localized: "Post on X")
            case .linkedIn: String(localized: "Post on LinkedIn")
            case .bluesky: String(localized: "Post on Bluesky")
            }
        }
    }

    /// The compose URL for `network`, with `text` prefilled, or `nil` when the text
    /// can't be encoded (not expected for any real string).
    static func composeURL(for network: Network, text: String) -> URL? {
        var components: URLComponents
        switch network {
        case .x:
            components = URLComponents(string: "https://x.com/intent/post")!
            components.queryItems = [URLQueryItem(name: "text", value: text)]
        case .linkedIn:
            components = URLComponents(string: "https://www.linkedin.com/feed/")!
            components.queryItems = [
                URLQueryItem(name: "shareActive", value: "true"),
                URLQueryItem(name: "text", value: text),
            ]
        case .bluesky:
            components = URLComponents(string: "https://bsky.app/intent/compose")!
            components.queryItems = [URLQueryItem(name: "text", value: text)]
        }
        return components.url
    }
}
