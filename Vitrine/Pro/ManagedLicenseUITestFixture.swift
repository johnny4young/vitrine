#if DEBUG && VITRINE_DIRECT_DOWNLOAD
    import CryptoKit
    import Foundation

    /// A complete managed-license graph for deterministic UI automation.
    ///
    /// The fixture exists only in Debug direct-download builds and requires both an explicit
    /// opt-in and an isolated defaults suite. It uses an ephemeral signing key, in-memory
    /// credential stores, a unique nonexistent temporary CLI path, and a local deactivator.
    /// Consequently, exercising Settings never reads a real Keychain item, exposes a real
    /// license key, mutates the user's CLI entitlement, or contacts Lemon Squeezy.
    @MainActor
    enum ManagedLicenseUITestFixture {
        static let environmentKey = "VITRINE_MANAGED_LICENSE_UI_TEST"

        static func makeEntitlements(environment: [String: String]) -> Entitlements? {
            guard environment[environmentKey] == "1",
                let defaultsSuite = environment["VITRINE_USER_DEFAULTS_SUITE"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !defaultsSuite.isEmpty
            else { return nil }

            let signingKey = Curve25519.Signing.PrivateKey()
            let licenseID = "vitrine-ui-test-license"
            let instanceID = "vitrine-ui-test-instance"
            guard
                let record = LicenseActivationRecord(
                    licenseKey: "vitrine-ui-test-key",
                    licenseID: licenseID,
                    instanceID: instanceID),
                let signedToken = try? LicenseSigner.sign(
                    LicenseToken(
                        licenseID: licenseID,
                        issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                    with: signingKey)
            else { return nil }

            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(token: signedToken),
                activationRecordStore: InMemoryActivationRecordStore(record: record),
                verifier: LicenseVerifier(publicKey: signingKey.publicKey),
                cliTokenFile: CLITokenFile(
                    url: FileManager.default.temporaryDirectory
                        .appendingPathComponent(
                            "vitrine-managed-license-ui-\(UUID().uuidString)",
                            isDirectory: true
                        )
                        .appendingPathComponent("pro-license.token", isDirectory: false)))
            return Entitlements(
                provider: provider,
                licenseDeactivationService: LicenseDeactivationService(
                    deactivator: LocalDeactivator(record: record)))
        }

        private final class InMemoryTokenStore: LicenseTokenStore {
            private var token: String?

            init(token: String) {
                self.token = token
            }

            func read() -> String? { token }

            func write(_ token: String?) -> Bool {
                self.token = token
                return true
            }
        }

        private final class InMemoryActivationRecordStore: LicenseActivationRecordStore {
            private var record: LicenseActivationRecord?

            init(record: LicenseActivationRecord) {
                self.record = record
            }

            func read() -> LicenseActivationRecord? { record }

            func write(_ record: LicenseActivationRecord?) -> Bool {
                self.record = record
                return true
            }
        }

        private nonisolated struct LocalDeactivator: LicenseKeyDeactivator {
            let record: LicenseActivationRecord

            func deactivate(
                licenseKey: String, instanceID: String
            ) async throws -> LicenseDeactivation {
                guard licenseKey == record.licenseKey,
                    instanceID == record.instanceID
                else {
                    throw LicenseDeactivationError.refused("UI fixture identity mismatch")
                }
                return LicenseDeactivation(licenseID: record.licenseID)
            }
        }
    }
#endif
