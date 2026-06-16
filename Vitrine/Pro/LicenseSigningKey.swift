import CryptoKit
import Foundation

#if VITRINE_DIRECT_DOWNLOAD
    /// The Ed25519 **private** key the direct-download build uses to sign a freshly-activated
    /// `LicenseToken` locally (CS-090, Architecture B). It is injected **only into the official
    /// release** at build time and is never committed to the repository.
    ///
    /// Injection mirrors the project's existing build-secret pattern (`VITRINE_ENTITLEMENTS_FILE`):
    /// the `VITRINE_LICENSE_SIGNING_KEY` environment variable (the base64 of the 32-byte raw
    /// private key) is interpolated by XcodeGen into the `VitrineLicenseSigningKey` Info.plist
    /// value at generate time, and read back here at runtime. A normal `make build`, a CI build,
    /// or anyone compiling from source leaves that variable unset → the value is empty →
    /// `embedded` is `nil` → the build **cannot mint a token and stays free**. That is the
    /// deliberate "free until the real key ships" state, and it is why the open-source build
    /// never grants PRO by itself.
    ///
    /// The matching **public** key must be embedded in `LicenseVerifier.embedded` (in source —
    /// it is not a secret) so the app and the `vitrine` CLI verify minted tokens offline. See
    /// `docs/ACTIVATION.md` for the keypair-generation + injection runbook.
    enum LicenseSigningKey {
        /// The Info.plist key XcodeGen fills from `${VITRINE_LICENSE_SIGNING_KEY}`.
        static let infoPlistKey = "VitrineLicenseSigningKey"

        /// The build-injected signing key, or `nil` when none was injected (a free build).
        static var embedded: Curve25519.Signing.PrivateKey? {
            key(fromBase64: Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
        }

        /// Decodes a raw-representation base64 private key, tolerating a missing, empty, or
        /// malformed value by returning `nil` (→ a free build) rather than trapping — the same
        /// defensive posture as the rest of the settings reads.
        static func key(fromBase64 base64: String?) -> Curve25519.Signing.PrivateKey? {
            guard let base64,
                !base64.isEmpty,
                // The unexpanded "$(VITRINE_LICENSE_SIGNING_KEY)" literal survives when the
                // variable is unset on some toolchains; treat it as "not injected".
                !base64.hasPrefix("$("),
                let raw = Data(base64Encoded: base64),
                let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
            else { return nil }
            return key
        }
    }
#endif
