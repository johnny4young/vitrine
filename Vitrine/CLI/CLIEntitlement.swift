import Foundation

/// The out-of-process PRO entitlement check for the `vitrine` CLI.
///
/// The CLI is a separate process from the app and a direct-download/Homebrew feature
/// (the sandboxed App Store build can't symlink a binary onto PATH), so it cannot read
/// the app's in-process `Entitlements` and there is no StoreKit↔CLI bridge. Instead the
/// app writes an **Ed25519-signed activation token** to a shared file on activation, and
/// the CLI re-verifies that signature itself against the embedded public key — it never
/// trusts a plain boolean. Verification is fully offline and
/// reuses the same `LicenseVerifier` the app uses.
///
/// A **Debug-only** env bypass (`VITRINE_PRO_UNLOCK=1`) unlocks the CLI for local
/// development. It is wrapped in `#if DEBUG`, so it is physically absent from a release
/// binary — the shipped CLI has no path to PRO except a signature-valid token. This is
/// the "bypass locally, never in releases" rule the app's `DebugUnlockProvider` follows.
enum CLIEntitlement {
    /// Whether PRO automation is unlocked for this CLI invocation.
    ///
    /// `tokenURL`, `verifier`, and `environment` are injectable so the verification is
    /// unit-testable with a minted token and a known key, without a real activation.
    static func isProUnlocked(
        tokenURL: URL = defaultTokenURL,
        verifier: LicenseVerifier = .embedded,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG
            if environment["VITRINE_PRO_UNLOCK"] == "1" { return true }
        #endif
        guard let raw = try? String(contentsOf: tokenURL, encoding: .utf8) else { return false }
        return verifier.verify(raw.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    /// The shared file the app writes the signed activation token to and the CLI reads it
    /// from. The direct-download app is **sandboxed**, so it writes inside its own
    /// container's Application Support (`LicenseKeyProvider` → `CLITokenFile.appContainerURL`,
    /// resolved through `.applicationSupportDirectory`). The CLI is **not** sandboxed, so its
    /// own `.applicationSupportDirectory` would be `~/Library/Application Support` — the wrong
    /// place. It therefore resolves that same physical file explicitly under the app's
    /// container from the real home, which is where the app actually wrote it.
    ///
    /// Without a token signed by the pinned production key, the CLI stays free here except
    /// under the Debug bypass — the correct "locked until activation" state.
    static var defaultTokenURL: URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return
            home
            .appendingPathComponent(
                "Library/Containers/\(appBundleIdentifier)/Data/Library/Application Support/Vitrine/pro-license.token",
                isDirectory: false)
    }

    /// The direct-download app's bundle identifier, whose sandbox container holds the shared
    /// token file. A fixed constant: the CLI is a separate process and cannot read the app's
    /// `Bundle.main`.
    static let appBundleIdentifier = "com.johnny4young.vitrine"
}
