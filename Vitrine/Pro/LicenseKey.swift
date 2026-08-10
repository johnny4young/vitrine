import CryptoKit
import Foundation
import Security

/// A local PRO license token for the direct-download build: a small signed payload
/// the app stores after a successful Lemon Squeezy activation, then verifies **offline** on
/// every launch — and which the `vitrine` CLI re-verifies — against an embedded Ed25519
/// public key.
///
/// This is an honor/convenience model, not anti-fork DRM. The signature lets the
/// CLI trust the app's activation without re-contacting Lemon Squeezy and rejects a
/// hand-edited token; it is not a defense against a determined forker (the code is open
/// source). In the embedded-key activation model (`docs/ACTIVATION.md`), the app signs the token **locally** at
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

/// Verifies a signed `LicenseToken` offline against an embedded Ed25519 public key.
/// Shared by the app and the CLI so both reach the same verdict from the same token bytes.
struct LicenseVerifier {
    /// The signing public key, or `nil` when an embedded representation is malformed. This
    /// value is safe to ship in source; only the matching private key is secret and injected
    /// into the official direct-download build.
    let publicKey: Curve25519.Signing.PublicKey?

    init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// Builds a verifier from shipped configuration. Invalid bytes produce an unconfigured
    /// verifier that rejects every token rather than terminating app or CLI startup.
    init(publicKeyBase64: String) {
        publicKey = Data(base64Encoded: publicKeyBase64).flatMap {
            try? Curve25519.Signing.PublicKey(rawRepresentation: $0)
        }
    }

    /// Decodes and verifies a `"<base64 payload>.<base64 signature>"` token, returning the
    /// payload only when the signature checks out. Any malformed, tampered, or
    /// wrongly-signed token returns `nil` — never a partial trust.
    func verify(_ token: String) -> LicenseToken? {
        guard let publicKey else { return nil }
        let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
            let payload = Data(base64Encoded: String(parts[0])),
            let signature = Data(base64Encoded: String(parts[1])),
            publicKey.isValidSignature(signature, for: payload),
            let decoded = try? JSONDecoder.licenseDecoder.decode(LicenseToken.self, from: payload)
        else { return nil }
        return decoded
    }

    /// The verifier built from the embedded **production** public key (embedded-key activation model).
    ///
    /// This is the public half of the direct-download license-signing keypair. The matching
    /// private half is injected only into the official release (`LicenseSigningKey.embedded`)
    /// and never committed; a token the app mints with it verifies here — and in the `vitrine`
    /// CLI — entirely offline. The exact bytes are pinned by
    /// `embeddedPublicKeyIsThePinnedProductionKey`, so a forgotten swap to a throwaway key cannot
    /// silently lock out paying users. `embeddedVerifierRejectsForeignTokens` guards against
    /// accepting a token signed by a foreign key.
    static let embedded = LicenseVerifier(publicKeyBase64: LicensePublicKeys.productionBase64)
}

private enum LicensePublicKeys {
    nonisolated static let productionBase64 = "GBiLsURlP+jwJGvfAJUAxTACaZbObIVBnBurkOQ+Fd0="
}

/// Mints a signed token from a private key. Under embedded-key activation model the **app** runs this
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
    /// Secret provider data needed to release exactly one machine seat later.
    ///
    /// The raw key intentionally lives outside `LicenseToken`: the signed token is mirrored to
    /// a CLI-readable file, while this record stays device-only in the Keychain. The custom
    /// decoder rejects empty or unbounded values before they reach networking or UI state.
    struct LicenseActivationRecord: Codable, Equatable, Sendable {
        nonisolated static let maximumLicenseKeyLength = 512
        nonisolated static let maximumIdentifierLength = 128

        let licenseKey: String
        let licenseID: String
        let instanceID: String

        init?(licenseKey: String, licenseID: String, instanceID: String) {
            let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let license = licenseID.trimmingCharacters(in: .whitespacesAndNewlines)
            let instance = instanceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty,
                key.count <= Self.maximumLicenseKeyLength,
                !license.isEmpty,
                license.count <= Self.maximumIdentifierLength,
                !instance.isEmpty,
                instance.count <= Self.maximumIdentifierLength
            else { return nil }
            self.licenseKey = key
            self.licenseID = license
            self.instanceID = instance
        }

        private enum CodingKeys: String, CodingKey {
            case licenseKey, licenseID, instanceID
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let key = try container.decode(String.self, forKey: .licenseKey)
            let license = try container.decode(String.self, forKey: .licenseID)
            let instance = try container.decode(String.self, forKey: .instanceID)
            guard
                let validated = Self(
                    licenseKey: key,
                    licenseID: license,
                    instanceID: instance)
            else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid activation record bounds."))
            }
            self = validated
        }
    }

    /// Where the signed PRO license token is persisted. The default is the
    /// **Keychain** (device-only, no iCloud sync) rather than `UserDefaults`, whose plist is
    /// world-readable by any process running as the user — making the token trivial to copy
    /// and replay across machines. Injectable so tests use an in-memory
    /// store without touching the real Keychain.
    protocol LicenseTokenStore {
        func read() -> String?
        @discardableResult func write(_ token: String?) -> Bool
    }

    /// Device-only storage for the raw activation credential and provider instance id.
    protocol LicenseActivationRecordStore {
        func read() -> LicenseActivationRecord?
        @discardableResult func write(_ record: LicenseActivationRecord?) -> Bool
    }

    /// Shared Keychain byte primitive for the separate token and secret-record accounts.
    /// Updating in place avoids the delete-before-add window that could discard a working
    /// entitlement if `SecItemAdd` later failed.
    private struct KeychainLicenseDataStore {
        let account: String

        private let service = "com.johnny4young.vitrine.pro"

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }

        func read() -> Data? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
            else { return nil }
            return item as? Data
        }

        @discardableResult
        func write(_ data: Data?) -> Bool {
            guard let data else {
                let status = SecItemDelete(baseQuery as CFDictionary)
                return status == errSecSuccess || status == errSecItemNotFound
            }

            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                attributes as CFDictionary)
            if updateStatus == errSecSuccess { return true }
            guard updateStatus == errSecItemNotFound else { return false }

            var add = baseQuery
            for (key, value) in attributes {
                add[key] = value
            }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
    }

    /// Persists the token as a device-only generic-password Keychain item under the app's own
    /// default access group. Not a hard DRM boundary (a determined user can still export their
    /// own item), but it raises seat-sharing well above `cat`-ing a preferences plist.
    struct KeychainLicenseStore: LicenseTokenStore {
        private let dataStore = KeychainLicenseDataStore(account: "license-token")

        func read() -> String? {
            dataStore.read().flatMap { String(data: $0, encoding: .utf8) }
        }

        @discardableResult
        func write(_ token: String?) -> Bool {
            dataStore.write(token?.data(using: .utf8))
        }
    }

    /// Stores the credential record under a separate device-only Keychain account. It is
    /// neither synced through iCloud nor mirrored to disk.
    struct KeychainLicenseActivationRecordStore: LicenseActivationRecordStore {
        private let dataStore = KeychainLicenseDataStore(account: "activation-record")

        func read() -> LicenseActivationRecord? {
            guard let data = dataStore.read() else { return nil }
            return try? JSONDecoder().decode(LicenseActivationRecord.self, from: data)
        }

        @discardableResult
        func write(_ record: LicenseActivationRecord?) -> Bool {
            guard let record else { return dataStore.write(nil) }
            guard let data = try? JSONEncoder().encode(record) else { return false }
            return dataStore.write(data)
        }
    }

    /// Mirrors the signed activation token into the shared file the bundled `vitrine` CLI
    /// reads, so the CLI's offline PRO check agrees with the app without a StoreKit
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
        /// so deactivation re-locks the CLI too. The result lets the provider avoid declaring
        /// a new activation complete while app and CLI entitlement state disagree.
        @discardableResult
        func write(_ token: String?) -> Bool {
            let fileManager = FileManager.default
            guard let token else {
                guard fileManager.fileExists(atPath: url.path) else { return true }
                do {
                    try fileManager.removeItem(at: url)
                    return true
                } catch {
                    return false
                }
            }
            do {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = token.data(using: .utf8) else { return false }
                try data.write(to: url, options: [.atomic])
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: url.path)
                return true
            } catch {
                return false
            }
        }
    }

    enum LicenseActivationCleanupResult: Equatable {
        case cleared
        case superseded
        case failed
    }

    /// The direct-download entitlement provider: PRO is unlocked by a locally-stored,
    /// signed `LicenseToken`, verified offline against the embedded public key at every launch
    /// and by the CLI. `LicenseActivationService` performs the one-time online activation and
    /// hands the minted token here; this provider persists it and mirrors it to the CLI file.
    @MainActor
    final class LicenseKeyProvider: EntitlementProvider {
        private let store: LicenseTokenStore
        private let activationRecordStore: LicenseActivationRecordStore
        private let verifier: LicenseVerifier
        private let cliTokenFile: CLITokenFile

        init(
            store: LicenseTokenStore = KeychainLicenseStore(),
            activationRecordStore: LicenseActivationRecordStore =
                KeychainLicenseActivationRecordStore(),
            verifier: LicenseVerifier = .embedded,
            cliTokenFile: CLITokenFile = CLITokenFile()
        ) {
            self.store = store
            self.activationRecordStore = activationRecordStore
            self.verifier = verifier
            self.cliTokenFile = cliTokenFile
        }

        /// Whether the stored token currently verifies — read instantly and offline at boot.
        var cachedIsPro: Bool { storedValidToken != nil }

        /// Re-verifies the stored token offline (no network). A lenient periodic Lemon Squeezy
        /// re-validation (refund/deactivation) layers on later; the offline signature check is
        /// the fast path and the CLI's only path.
        func currentIsPro() async -> Bool { storedValidToken != nil }

        /// The currently manageable seat record. A record can survive a partial local write,
        /// allowing the user to release a remotely-consumed seat instead of orphaning it.
        var activationRecordForDeactivation: LicenseActivationRecord? {
            activationRecordStore.read()
        }

        /// A valid pre-record activation remains PRO for compatibility, but cannot claim to
        /// know the provider instance id required for in-app seat release.
        var hasLegacyActivation: Bool {
            cachedIsPro && activationRecordStore.read() == nil
        }

        /// Persists the secret record before the signed entitlement. Every value is validated
        /// and the token's traceable license id must match the provider record. A different
        /// recoverable record is never overwritten, because doing so would lose the only data
        /// capable of releasing its already-consumed remote seat.
        @discardableResult
        func setActivation(signedToken: String, record: LicenseActivationRecord) -> Bool {
            guard verifier.verify(signedToken)?.licenseID == record.licenseID else { return false }
            guard activationRecordStore.read().map({ $0 == record }) ?? true else { return false }
            guard activationRecordStore.write(record),
                activationRecordStore.read() == record
            else { return false }
            guard store.write(signedToken), storedValidToken?.licenseID == record.licenseID
            else { return false }
            guard cliTokenFile.write(signedToken) else {
                // Keep the record for remote seat recovery, but never leave app and CLI
                // entitlement state disagreeing after a newly activated seat.
                _ = store.write(nil)
                return false
            }
            return true
        }

        /// Clears only the exact record that initiated the remote request. After an `await`,
        /// a newer activation may exist; comparing the full record prevents the old response
        /// from deleting it. Token and CLI cleanup happen before the credential record so a
        /// failed cleanup can be retried without losing the provider instance id.
        func clearActivation(
            ifMatching expected: LicenseActivationRecord
        ) -> LicenseActivationCleanupResult {
            guard activationRecordStore.read() == expected else { return .superseded }
            let originalToken = store.read()
            if let token = originalToken,
                let currentLicenseID = verifier.verify(token)?.licenseID,
                currentLicenseID != expected.licenseID
            {
                return .superseded
            }

            guard cliTokenFile.write(nil) else { return .failed }
            guard store.write(nil) else {
                if let originalToken { _ = cliTokenFile.write(originalToken) }
                return .failed
            }
            guard activationRecordStore.write(nil) else { return .failed }
            return .cleared
        }

        private var storedValidToken: LicenseToken? {
            guard let token = store.read() else { return nil }
            return verifier.verify(token)
        }
    }
#endif
