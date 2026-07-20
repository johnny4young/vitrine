import Foundation

#if canImport(Security)
    import Security
#endif

// MARK: - Network capability gate

/// Whether this build is actually permitted to reach the network for a URL
/// capture.
///
/// URL capture stays **disabled until the app target includes**
/// `com.apple.security.network.client`. local rendering ships without that entitlement
/// (the core is fully local), so a network-free build provably cannot load a remote
/// page even if the URL path is wired up. This gate reads the running app's own
/// entitlement at launch — there is no network call and no private API — so the
/// renderer can refuse early with a clear reason rather than failing deep inside
/// WebKit.
enum NetworkCapability {
    /// The entitlement key that, when present and true on the app target, enables
    /// outbound network access under the App Sandbox.
    static let networkClientEntitlement = "com.apple.security.network.client"

    /// Whether the current process carries the network-client entitlement.
    ///
    /// Probed from the running task's own entitlements via `SecTask`; the result is
    /// stable for the life of the process, so it is computed once and cached. On a
    /// platform without the Security framework (it ships on macOS, where Vitrine
    /// runs) this conservatively reports `false`, keeping URL capture disabled.
    static var hasNetworkClientEntitlement: Bool { cachedValue }

    /// Whether URL capture is enabled in this build. It is gated solely on the
    /// network entitlement: without it, the feature is off regardless of any user
    /// setting, because a sandboxed app with no network entitlement cannot load a
    /// remote page.
    static var isURLCaptureEnabled: Bool { hasNetworkClientEntitlement }

    /// The cached entitlement probe, evaluated at most once.
    private static let cachedValue: Bool = readEntitlement()

    /// Reads the `com.apple.security.network.client` entitlement from the current
    /// task. Returns `false` when the entitlement is absent, false, or cannot be
    /// read — every "not granted" outcome maps to the safe answer.
    private static func readEntitlement() -> Bool {
        #if canImport(Security)
            guard let task = SecTaskCreateFromSelf(nil) else { return false }
            let value = SecTaskCopyValueForEntitlement(
                task, networkClientEntitlement as CFString, nil)
            guard let allowed = value as? Bool else { return false }
            return allowed
        #else
            return false
        #endif
    }
}
