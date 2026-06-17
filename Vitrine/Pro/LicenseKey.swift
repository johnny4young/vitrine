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
/// source). Architecture B (`docs/ACTIVATION.md`): the app signs the token **locally** at
/// activation with a private key injected only into the official release build
/// (`LicenseSigningKey.embedded`). A build compiled from source has no such key, so it cannot
/// mint a token and stays free — the public half lives in source for offline verification.
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
    /// The signing public key, embedded in the build. This value is safe to ship in source;
    /// only the matching private key is secret and injected into the official
    /// direct-download build.
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

    /// The verifier built from the embedded **production** public key (CS-090, Architecture B).
    ///
    /// This is the public half of the direct-download license-signing keypair. The matching
    /// private half is injected only into the official release (`LicenseSigningKey.embedded`)
    /// and never committed; a token the app mints with it verifies here — and in the `vitrine`
    /// CLI — entirely offline. The exact bytes are pinned by
    /// `embeddedPublicKeyIsThePinnedProductionKey` (so a forgotten swap to a throwaway key can't
    /// silently lock out paying users, audit P1-Security-6), and
    /// `embeddedVerifierRejectsForeignTokens` guards that no foreign-signed token validates.
    static let embedded = LicenseVerifier(
        publicKey: try! Curve25519.Signing.PublicKey(
            rawRepresentation: Data(base64Encoded: "GBiLsURlP+jwJGvfAJUAxTACaZbObIVBnBurkOQ+Fd0=")!)
    )
}

/// Mints a signed token from a private key (CS-090). Under Architecture B the **app** runs this
/// at activation, with the build-injected `LicenseSigningKey.embedded`; the same function backs
/// the unit tests' mint → verify → tamper path with a throwaway development key.
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

    /// Mirrors the signed activation token into the shared file the bundled `vitrine` CLI
    /// reads (CS-094), so the CLI's offline PRO check agrees with the app without a StoreKit
    /// or IPC bridge. The sandboxed app writes inside its **own container's** Application
    /// Support; the non-sandboxed CLI reads that exact physical path via
    /// `CLIEntitlement.defaultTokenURL`. The `url` is injectable so tests use a temp file and
    /// never touch the real container.
    struct CLITokenFile {
        /// The app-side path: the (container) Application Support resolved through
        /// `.applicationSupportDirectory`, which inside the App Sandbox *is* the container —
        /// the same bytes `CLIEntitlement.defaultTokenURL` points the CLI at.
        static var appContainerURL: URL {
            let base =
                (try? FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            return base.appendingPathComponent("Vitrine/pro-license.token", isDirectory: false)
        }

        var url: URL = CLITokenFile.appContainerURL

        /// Writes the token `0600` (creating the directory), or removes the file on `nil` —
        /// so deactivation re-locks the CLI too. Failures are swallowed: the CLI mirror is a
        /// convenience, never a gate on the app's own (Keychain-backed) entitlement.
        func write(_ token: String?) {
            let fileManager = FileManager.default
            guard let token else {
                try? fileManager.removeItem(at: url)
                return
            }
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? token.data(using: .utf8)?.write(to: url, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    /// The direct-download entitlement provider (CS-090): PRO is unlocked by a locally-stored,
    /// signed `LicenseToken`, verified offline against the embedded public key at every launch
    /// and by the CLI. `LicenseActivationService` performs the one-time online activation and
    /// hands the minted token here; this provider persists it and mirrors it to the CLI file.
    @MainActor
    final class LicenseKeyProvider: EntitlementProvider {
        private let store: LicenseTokenStore
        private let verifier: LicenseVerifier
        private let cliTokenFile: CLITokenFile

        init(
            store: LicenseTokenStore = KeychainLicenseStore(),
            verifier: LicenseVerifier = .embedded,
            cliTokenFile: CLITokenFile = CLITokenFile()
        ) {
            self.store = store
            self.verifier = verifier
            self.cliTokenFile = cliTokenFile
        }

        /// Whether the stored token currently verifies — read instantly and offline at boot.
        var cachedIsPro: Bool { storedValidToken != nil }

        /// Re-verifies the stored token offline (no network). A lenient periodic Lemon Squeezy
        /// re-validation (refund/deactivation) layers on later; the offline signature check is
        /// the fast path and the CLI's only path.
        func currentIsPro() async -> Bool { storedValidToken != nil }

        /// Stores a freshly-issued signed token after a successful activation (and mirrors it
        /// to the CLI file), or clears both on deactivation. Validated before storing, so a
        /// bad token never sticks and never reaches the CLI.
        func setToken(_ token: String?) {
            if let token, verifier.verify(token) != nil {
                store.write(token)
                cliTokenFile.write(token)
            } else {
                store.write(nil)
                cliTokenFile.write(nil)
            }
        }

        private var storedValidToken: LicenseToken? {
            guard let token = store.read() else { return nil }
            return verifier.verify(token)
        }
    }
#endif
