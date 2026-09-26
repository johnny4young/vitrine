#if DEBUG && VITRINE_DIRECT_DOWNLOAD
    import CryptoKit
    import Foundation
    import VitrineDomain

    /// A complete managed-license graph for deterministic UI automation.
    ///
    /// The fixture exists only in Debug direct-download builds and requires both an explicit
    /// opt-in and an isolated defaults suite. It uses an ephemeral signing key, in-memory
    /// credential stores, an isolated temporary CLI path (or a nondirectory for write failure),
    /// and local activation/deactivation providers.
    /// Consequently, exercising Settings never reads a real Keychain item, exposes a real
    /// license key, mutates the user's CLI entitlement, or contacts Lemon Squeezy.
    enum ManagedLicenseUITestFixture {
        static let environmentKey = "VITRINE_MANAGED_LICENSE_UI_TEST"

        enum Mode: String {
            case activeLicense = "1"
            case activationSuccess = "activation-success"
            case activationPersistenceFailure = "activation-persistence-failure"
        }

        static func makeEntitlements(environment: [String: String]) -> Entitlements? {
            guard let mode = environment[environmentKey].flatMap(Mode.init(rawValue:)),
                let defaultsSuite = environment["VITRINE_USER_DEFAULTS_SUITE"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !defaultsSuite.isEmpty
            else { return nil }
            let newActivation = mode != .activeLicense
            let activationFailure = mode == .activationPersistenceFailure

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
                store: InMemoryTokenStore(
                    token: newActivation ? nil : signedToken, rejectsClear: activationFailure),
                activationRecordStore: InMemoryActivationRecordStore(
                    record: newActivation ? nil : record),
                verifier: LicenseVerifier(publicKey: signingKey.publicKey),
                cliTokenFile: CLITokenFile(
                    // /dev/null is not a directory: creating its child fails without writing data.
                    url: activationFailure
                        ? URL(fileURLWithPath: "/dev/null/vitrine-ui-token")
                        : FileManager.default.temporaryDirectory
                            .appendingPathComponent(
                                "vitrine-managed-license-ui-\(UUID().uuidString)",
                                isDirectory: true
                            )
                            .appendingPathComponent("pro-license.token", isDirectory: false)))
            return Entitlements(
                provider: provider,
                licenseActivationService: LicenseActivationService(
                    validator: LocalValidator(record: record), signingKey: signingKey),
                licenseDeactivationService: LicenseDeactivationService(
                    deactivator: LocalDeactivator(record: record)))
        }

        private final class InMemoryTokenStore: LicenseTokenStore {
            private var token: String?

            private let rejectsClear: Bool

            init(token: String?, rejectsClear: Bool = false) {
                self.token = token
                self.rejectsClear = rejectsClear
            }

            func read() -> String? { token }

            func write(_ token: String?) -> Bool {
                if token == nil, rejectsClear { return false }
                self.token = token
                return true
            }
        }

        private final class InMemoryActivationRecordStore: LicenseActivationRecordStore {
            private var record: LicenseActivationRecord?

            init(record: LicenseActivationRecord?) {
                self.record = record
            }

            func read() -> LicenseActivationRecord? { record }

            func write(_ record: LicenseActivationRecord?) -> Bool {
                self.record = record
                return true
            }
        }

        private nonisolated struct LocalValidator: LicenseKeyValidator {
            let record: LicenseActivationRecord

            func activate(
                licenseKey: String, instanceName: String
            ) async throws -> LicenseActivation {
                guard licenseKey == record.licenseKey else {
                    throw LicenseActivationError.invalidKey
                }
                return LicenseActivation(
                    licenseID: record.licenseID, instanceID: record.instanceID, status: "active")
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
