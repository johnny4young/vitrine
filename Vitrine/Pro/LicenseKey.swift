import CryptoKit
import Foundation
import Security

/// A local PRO license token for the direct-download build (CS-090): a small signed payload
/// the app stores after a successful Lemon Squeezy activation, then verifies **offline** on
/// every launch — and which the `vitrine` CLI re-verifies — against an embedded Ed25519
/// public key.
///
/// Honor/convenience model (the epic is explicit: not anti-fork DRM). The signature lets the
/// CLI trust the app's activation without re-contacting Lemon Squeezy and rejects a
/// hand-edited token; it is not a defense against a determined forker (the code is open
/// source). Tokens are signed **server-side** at activation, so the private key is never
/// shipped — the same posture as the Sparkle appcast key (`SUPublicEDKey`).
struct LicenseToken: Codable, Equatable {
    /// The opaque license identifier (e.g. the Lemon Squeezy order/license id) — never a
    /// secret, carried so a token is traceable to its purchase.
    let licenseID: String
    /// When the token was issued, by the signer's clock. Informational; the gate does not
    /// expire a lifetime license.
    let issuedAt: Date
}

/// Verifies a signed `LicenseToken` offline against an embedded Ed25519 public key (CS-090).
/// Shared by the app and the CLI so both reach the same verdict from the same token bytes.
struct LicenseVerifier {
    /// The signing public key, embedded in the build. Replaced with the real Lemon Squeezy
    /// signing key once that pipeline exists; the placeholder below has no known private
    /// half, so no externally-minted token can validate and the build stays free.
    let publicKey: Curve25519.Signing.PublicKey

    /// Decodes and verifies a `"<base64 payload>.<base64 signature>"` token, returning the
    /// payload only when the signature checks out. Any malformed, tampered, or
    /// wrongly-signed token returns `nil` — never a partial trust.
    func verify(_ token: String) -> LicenseToken? {
        let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
            let payload = Data(base64Encoded: String(parts[0])),
            let signature = Data(base64Encoded: String(parts[1])),
            publicKey.isValidSignature(signature, for: payload),
            let decoded = try? JSONDecoder.licenseDecoder.decode(LicenseToken.self, from: payload)
        else { return nil }
        return decoded
    }

    /// The verifier built from the embedded public key. The placeholder uses a throwaway
    /// random key (its private half is discarded), so until the real Lemon Squeezy key is
    /// embedded no token can validate and the direct-download build is free by default.
    static let embedded = LicenseVerifier(
        publicKey: Curve25519.Signing.PrivateKey().publicKey)
}

/// Mints a signed token from a private key (CS-090). This runs **server-side** at activation,
/// where the private key lives; it is included here so the verifier has a tested counterpart
/// and the unit tests can exercise the full mint → verify → tamper path. The app never holds
/// the private key in production.
enum LicenseSigner {
    static func sign(
        _ token: LicenseToken, with privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let payload = try JSONEncoder.licenseEncoder.encode(token)
        let signature = try privateKey.signature(for: payload)
        return payload.base64EncodedString() + "." + signature.base64EncodedString()
    }
}

extension JSONEncoder {
    /// Deterministic encoder for license payloads (sorted keys + ISO-8601 dates) so the
    /// signed bytes are stable across encodes. Computed (not a shared instance) to stay
    /// concurrency-safe.
    fileprivate static var licenseEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var licenseDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

#if VITRINE_DIRECT_DOWNLOAD
    /// Where the signed PRO license token is persisted (CS-090). The default is the
    /// **Keychain** (device-only, no iCloud sync) rather than `UserDefaults`, whose plist is
    /// world-readable by any process running as the user — making the token trivial to copy
    /// and replay across machines (audit P1-Security-1). Injectable so tests use an in-memory
    /// store without touching the real Keychain.
    protocol LicenseTokenStore {
        func read() -> String?
        func write(_ token: String?)
    }

    /// Persists the token as a device-only generic-password Keychain item under the app's own
    /// default access group. Not a hard DRM boundary (a determined user can still export their
    /// own item), but it raises seat-sharing well above `cat`-ing a preferences plist.
    struct KeychainLicenseStore: LicenseTokenStore {
        private let service = "com.johnny4young.vitrine.pro"
        private let account = "license-token"

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }

        func read() -> String? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                let data = item as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        }

        func write(_ token: String?) {
            // Replace any existing item: delete then (if a token) add, so write is idempotent.
            SecItemDelete(baseQuery as CFDictionary)
            guard let token, let data = token.data(using: .utf8) else { return }
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// The direct-download entitlement provider (CS-090): PRO is unlocked by a locally-stored,
    /// signed `LicenseToken`, verified offline against the embedded public key at every launch
    /// and by the CLI. Activation (a one-time Lemon Squeezy online check that yields a signed
    /// token) is wired when the LS account exists; until then no token is stored, so it is free.
    @MainActor
    final class LicenseKeyProvider: EntitlementProvider {
        private let store: LicenseTokenStore
        private let verifier: LicenseVerifier

        init(
            store: LicenseTokenStore = KeychainLicenseStore(), verifier: LicenseVerifier = .embedded
        ) {
            self.store = store
            self.verifier = verifier
        }

        /// Whether the stored token currently verifies — read instantly and offline at boot.
        var cachedIsPro: Bool { storedValidToken != nil }

        /// Re-verifies the stored token offline (no network). A lenient periodic Lemon Squeezy
        /// re-validation (refund/deactivation) layers on later; the offline signature check is
        /// the fast path and the CLI's only path.
        func currentIsPro() async -> Bool { storedValidToken != nil }

        /// Stores a freshly-issued signed token after a successful activation, or clears it on
        /// deactivation. Validated before storing, so a bad token never sticks.
        func setToken(_ token: String?) {
            if let token, verifier.verify(token) != nil {
                store.write(token)
            } else {
                store.write(nil)
            }
        }

        private var storedValidToken: LicenseToken? {
            guard let token = store.read() else { return nil }
            return verifier.verify(token)
        }
    }
#endif
