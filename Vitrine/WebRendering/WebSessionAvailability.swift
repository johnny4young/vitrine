import Foundation

/// Whether Vitrine can sign in to a site for the user, and what to tell them when it
/// cannot.
///
/// Capturing a page that lives behind a login needs cookies, and cookies ride the
/// persistent data store (`WebSnapshotConfig.DataStoreMode.persistent`) — which is
/// opt-in and, until the user has actually signed in *inside Vitrine*, empty. That is
/// the gap this type gates: the app's own store never receives a session from Safari or
/// Chrome, because WebKit isolates website data per application.
///
/// Pure and injectable so every branch is unit-testable without a window, a network, or
/// an entitlement.
enum WebSessionAvailability {
    /// Why signing in is not offered, in the order the user has to resolve them.
    enum Blocker: Equatable {
        /// The build cannot reach the network at all (App Store / CLI targets ship
        /// without the entitlement), so no site can be loaded to sign in to.
        case captureUnavailable
        /// The user has not opted into a persistent session, so a sign-in would be
        /// discarded the moment the window closed.
        case sessionNotEnabled
        /// There is no usable address to sign in to yet.
        case noValidURL
    }

    /// The first unmet requirement, or `nil` when signing in can proceed.
    ///
    /// Ordered deliberately: an entitlement the build lacks can never be resolved by the
    /// user, the opt-in can be resolved in Settings, and the address is the thing they
    /// are already typing. Reporting the earliest blocker keeps the UI from asking for a
    /// URL to reach a feature this build does not have.
    static func blocker(
        isCaptureEnabled: Bool,
        usesLoggedInSession: Bool,
        urlText: String,
        allowsLoopback: Bool = false
    ) -> Blocker? {
        guard isCaptureEnabled else { return .captureUnavailable }
        guard usesLoggedInSession else { return .sessionNotEnabled }
        guard
            (try? WebSnapshotConfig.validate(
                captureURLString: urlText, allowLoopback: allowsLoopback)) != nil
        else { return .noValidURL }
        return nil
    }

    /// Whether the sign-in affordance should be offered for this state.
    static func canSignIn(
        isCaptureEnabled: Bool,
        usesLoggedInSession: Bool,
        urlText: String,
        allowsLoopback: Bool = false
    ) -> Bool {
        blocker(
            isCaptureEnabled: isCaptureEnabled, usesLoggedInSession: usesLoggedInSession,
            urlText: urlText, allowsLoopback: allowsLoopback) == nil
    }

    /// The site a sign-in would apply to, for use in UI copy ("Sign in to github.com").
    /// `nil` when the text is not a capturable address.
    static func siteLabel(for urlText: String, allowsLoopback: Bool = false) -> String? {
        guard
            let url = try? WebSnapshotConfig.validate(
                captureURLString: urlText, allowLoopback: allowsLoopback)
        else { return nil }
        return url.host
    }
}
