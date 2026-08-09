import CryptoKit
import Foundation
import Testing

@testable import Vitrine

#if VITRINE_DIRECT_DOWNLOAD
    /// Direct-download license activation (embedded-key activation model): the Lemon Squeezy response
    /// parser, the activation service's local minting, and the end-to-end handoff from the app's
    /// activation to the `vitrine` CLI's offline check — all driven by a throwaway **development**
    /// keypair, never the network or the production key.
    @Suite("License activation")
    @MainActor
    struct LicenseActivationTests {
        /// A canned validator so the service is tested without the Lemon Squeezy network.
        nonisolated struct StubValidator: LicenseKeyValidator {
            var result: Result<LicenseActivation, LicenseActivationError>
            func activate(
                licenseKey: String, instanceName: String
            ) async throws -> LicenseActivation {
                try result.get()
            }
        }

        /// A validator that would fail the outcome if the service tried to call it.
        nonisolated struct UnexpectedValidator: LicenseKeyValidator {
            func activate(
                licenseKey: String, instanceName: String
            ) async throws -> LicenseActivation {
                throw LicenseActivationError.network("unexpected validation call")
            }
        }

        nonisolated struct StubDeactivator: LicenseKeyDeactivator {
            var result: Result<LicenseDeactivation, LicenseDeactivationError>

            func deactivate(
                licenseKey: String, instanceID: String
            ) async throws -> LicenseDeactivation {
                try result.get()
            }
        }

        /// An in-memory token store so the provider round-trip never touches the real Keychain.
        final class InMemoryTokenStore: LicenseTokenStore {
            private var token: String?
            func read() -> String? { token }
            func write(_ token: String?) -> Bool {
                self.token = token
                return true
            }
        }

        final class InMemoryActivationRecordStore: LicenseActivationRecordStore {
            private var record: LicenseActivationRecord?
            func read() -> LicenseActivationRecord? { record }
            func write(_ record: LicenseActivationRecord?) -> Bool {
                self.record = record
                return true
            }
        }

        private func tempTokenURL() -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("vitrine-activation-test-\(UUID().uuidString)")
                .appendingPathComponent("pro-license.token", isDirectory: false)
        }

        // MARK: - Lemon Squeezy response parsing

        @Test func parsesASuccessfulActivation() throws {
            let json = Data(
                """
                {"activated":true,"error":null,
                 "license_key":{"id":42,"status":"active","test_mode":false},
                 "instance":{"id":"inst-1","name":"Mac"},
                 "meta":{"store_id":408765,"product_id":1156861}}
                """.utf8)
            let activation = try LemonSqueezyValidator.parse(status: 200, data: json)
            #expect(
                activation
                    == LicenseActivation(licenseID: "42", instanceID: "inst-1", status: "active"))
        }

        @Test func parsesARealLemonSqueezyResponseShape() throws {
            // The full field set a real Lemon Squeezy /v1/licenses/activate response carries
            // (values anonymized), to pin that the parser tracks LS's actual names/types and
            // that the many extra fields it sends — meta, activation_limit, test_mode, … — are
            // ignored rather than breaking decoding.
            let json = Data(
                """
                {"activated":true,"error":null,
                 "instance":{"id":"d6097f9f-7154-4b57-a7b9-5616c3efb037","name":"Mac",
                             "created_at":"2026-01-01T00:00:00.000000Z"},
                 "license_key":{"id":1433534,"status":"active","key":"XXXX-XXXX-XXXX-XXXX",
                                "activation_limit":3,"activation_usage":1,"expires_at":null,
                                "created_at":"2026-01-01T00:00:00.000000Z","test_mode":false},
                 "meta":{"store_id":408765,"product_id":1156861,
                         "product_name":"Vitrine PRO"}}
                """.utf8)
            let activation = try LemonSqueezyValidator.parse(status: 200, data: json)
            #expect(
                activation
                    == LicenseActivation(
                        licenseID: "1433534",
                        instanceID: "d6097f9f-7154-4b57-a7b9-5616c3efb037", status: "active"))
        }

        @Test func parseMapsTheActivationLimitToATypedError() {
            let json = Data(
                #"{"activated":false,"error":"This license key has reached the activation limit."}"#
                    .utf8)
            #expect(throws: LicenseActivationError.activationLimitReached) {
                try LemonSqueezyValidator.parse(status: 400, data: json)
            }
        }

        @Test func parseMapsAnUnknownKeyToInvalidKey() {
            let json = Data(#"{"activated":false,"error":"license_key not found"}"#.utf8)
            #expect(throws: LicenseActivationError.invalidKey) {
                try LemonSqueezyValidator.parse(status: 404, data: json)
            }
        }

        @Test func parseRejectsAKeyForAnotherProductOrStore() {
            func response(storeID: Int, productID: Int, testMode: Bool = false) -> Data {
                Data(
                    """
                    {"activated":true,"error":null,
                     "license_key":{"id":42,"status":"active","test_mode":\(testMode)},
                     "instance":{"id":"inst-1","name":"Mac"},
                     "meta":{"store_id":\(storeID),"product_id":\(productID)}}
                    """.utf8)
            }

            for data in [
                response(
                    storeID: LemonSqueezyValidator.expectedStoreID + 1,
                    productID: LemonSqueezyValidator.expectedProductID),
                response(
                    storeID: LemonSqueezyValidator.expectedStoreID,
                    productID: LemonSqueezyValidator.expectedProductID + 1),
                response(
                    storeID: LemonSqueezyValidator.expectedStoreID,
                    productID: LemonSqueezyValidator.expectedProductID,
                    testMode: true),
            ] {
                #expect(throws: LicenseActivationError.invalidKey) {
                    try LemonSqueezyValidator.parse(status: 200, data: data)
                }
            }
        }

        @Test func parseRejectsASuccessWithoutATraceableLicenseID() {
            let json = Data(
                """
                {"activated":true,"error":null,
                 "license_key":{"status":"active","test_mode":false},
                 "instance":{"id":"inst-1","name":"Mac"},
                 "meta":{"store_id":408765,"product_id":1156861}}
                """.utf8)
            #expect(throws: LicenseActivationError.invalidKey) {
                try LemonSqueezyValidator.parse(status: 200, data: json)
            }
        }

        @Test func parseRejectsAnUnreadableBodyAsNetwork() {
            #expect(throws: LicenseActivationError.self) {
                try LemonSqueezyValidator.parse(status: 200, data: Data("not json".utf8))
            }
        }

        @Test func productionValidatorUsesAPrivateBoundedSession() {
            let validator = LemonSqueezyValidator()
            #expect(validator.session !== URLSession.shared)
            #expect(
                validator.session.configuration.requestCachePolicy
                    == .reloadIgnoringLocalCacheData)
            #expect(
                validator.session.configuration.timeoutIntervalForRequest
                    == LemonSqueezyValidator.requestTimeout)
            #expect(
                validator.session.configuration.timeoutIntervalForResource
                    == LemonSqueezyValidator.requestTimeout)
        }

        // MARK: - Lemon Squeezy deactivation

        @Test func parsesSuccessfulDeactivationForActiveOrInactiveLicenses() throws {
            for status in ["active", "inactive"] {
                let json = Data(
                    """
                    {"deactivated":true,"error":null,
                     "license_key":{"id":42,"status":"\(status)","test_mode":false,
                                    "activation_usage":0},
                     "meta":{"store_id":408765,"product_id":1156861}}
                    """.utf8)
                #expect(
                    try LemonSqueezyValidator.parseDeactivation(status: 200, data: json)
                        == LicenseDeactivation(licenseID: "42"))
            }
        }

        @Test func parseDeactivationRecognizesOnlyAConclusiveMissingInstance() {
            let missingInstance = Data(
                #"{"deactivated":false,"error":"License key instance not found."}"#.utf8)
            #expect(throws: LicenseDeactivationError.alreadyInactive) {
                try LemonSqueezyValidator.parseDeactivation(status: 404, data: missingInstance)
            }

            let missingKey = Data(
                #"{"deactivated":false,"error":"License key not found."}"#.utf8)
            #expect(throws: LicenseDeactivationError.refused("License key not found.")) {
                try LemonSqueezyValidator.parseDeactivation(status: 404, data: missingKey)
            }
        }

        @Test func parseDeactivationRejectsForeignTestOrUntraceableResponses() {
            func response(
                storeID: Int = LemonSqueezyValidator.expectedStoreID,
                productID: Int = LemonSqueezyValidator.expectedProductID,
                licenseID: String = "42",
                testMode: Bool = false
            ) -> Data {
                Data(
                    """
                    {"deactivated":true,"error":null,
                     "license_key":{"id":\(licenseID),"test_mode":\(testMode)},
                     "meta":{"store_id":\(storeID),"product_id":\(productID)}}
                    """.utf8)
            }

            for data in [
                response(storeID: LemonSqueezyValidator.expectedStoreID + 1),
                response(productID: LemonSqueezyValidator.expectedProductID + 1),
                response(testMode: true),
                response(licenseID: "null"),
            ] {
                #expect(throws: LicenseDeactivationError.self) {
                    try LemonSqueezyValidator.parseDeactivation(status: 200, data: data)
                }
            }
        }

        @Test func parseDeactivationRejectsUnreadableOrNonSuccessBodies() {
            #expect(throws: LicenseDeactivationError.network("Unreadable response (HTTP 200).")) {
                try LemonSqueezyValidator.parseDeactivation(
                    status: 200, data: Data("not json".utf8))
            }
            let misleading = Data(
                """
                {"deactivated":true,"error":null,
                 "license_key":{"id":42,"test_mode":false},
                 "meta":{"store_id":408765,"product_id":1156861}}
                """.utf8)
            #expect(throws: LicenseDeactivationError.self) {
                try LemonSqueezyValidator.parseDeactivation(status: 500, data: misleading)
            }
        }

        @Test func deactivationRequestUsesTheDedicatedBoundedFormContract() throws {
            let endpoint = try #require(
                URL(string: "https://example.test/v1/licenses/deactivate"))
            let request = LemonSqueezyValidator.deactivationRequest(
                licenseKey: "KEY VALUE", instanceID: "instance/1", endpoint: endpoint)
            #expect(request.url == endpoint)
            #expect(request.httpMethod == "POST")
            #expect(
                request.value(forHTTPHeaderField: "Content-Type")
                    == "application/x-www-form-urlencoded")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(request.timeoutInterval == LemonSqueezyValidator.requestTimeout)
            #expect(
                request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
                    == "instance_id=instance%2F1&license_key=KEY%20VALUE")
        }

        // MARK: - Activation service (local minting)

        @Test func serviceMintsAVerifiableTokenOnSuccess() async throws {
            let key = Curve25519.Signing.PrivateKey()
            let service = LicenseActivationService(
                validator: StubValidator(
                    result: .success(
                        LicenseActivation(licenseID: "ORD-9", instanceID: "i", status: "active"))),
                signingKey: key,
                now: { Date(timeIntervalSince1970: 1_700_000_000) })
            guard
                case .activated(let token, let record) =
                    await service.activate(licenseKey: " KEY ")
            else {
                Issue.record("expected .activated")
                return
            }
            // The minted token verifies against the matching public key and carries the id.
            #expect(LicenseVerifier(publicKey: key.publicKey).verify(token)?.licenseID == "ORD-9")
            #expect(
                record
                    == LicenseActivationRecord(
                        licenseKey: "KEY", licenseID: "ORD-9", instanceID: "i"))
        }

        @Test func activationRecordRejectsEmptyOversizedAndCorruptValues() throws {
            #expect(
                LicenseActivationRecord(licenseKey: " ", licenseID: "id", instanceID: "i")
                    == nil)
            #expect(
                LicenseActivationRecord(
                    licenseKey: String(
                        repeating: "K", count: LicenseActivationRecord.maximumLicenseKeyLength + 1),
                    licenseID: "id", instanceID: "i") == nil)
            #expect(
                LicenseActivationRecord(
                    licenseKey: "KEY",
                    licenseID: String(
                        repeating: "L", count: LicenseActivationRecord.maximumIdentifierLength + 1),
                    instanceID: "i") == nil)

            let valid = try #require(
                LicenseActivationRecord(
                    licenseKey: " KEY ", licenseID: " 42 ", instanceID: " inst "))
            let roundTrip = try JSONDecoder().decode(
                LicenseActivationRecord.self,
                from: JSONEncoder().encode(valid))
            #expect(
                roundTrip
                    == LicenseActivationRecord(
                        licenseKey: "KEY", licenseID: "42", instanceID: "inst"))

            let corrupt = Data(
                #"{"licenseKey":"","licenseID":"42","instanceID":"inst"}"#.utf8)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(LicenseActivationRecord.self, from: corrupt)
            }
        }

        @Test func deactivationServiceRequiresTheSameTraceableLicense() async throws {
            let record = try #require(
                LicenseActivationRecord(
                    licenseKey: "KEY", licenseID: "42", instanceID: "inst"))
            let success = LicenseDeactivationService(
                deactivator: StubDeactivator(
                    result: .success(LicenseDeactivation(licenseID: "42"))))
            #expect(await success.deactivate(record: record) == .deactivated)

            let mismatch = LicenseDeactivationService(
                deactivator: StubDeactivator(
                    result: .success(LicenseDeactivation(licenseID: "99"))))
            #expect(await mismatch.deactivate(record: record) == .refused)

            let absent = LicenseDeactivationService(
                deactivator: StubDeactivator(result: .failure(.alreadyInactive)))
            #expect(await absent.deactivate(record: record) == .alreadyInactive)

            let offline = LicenseDeactivationService(
                deactivator: StubDeactivator(result: .failure(.network("offline"))))
            #expect(await offline.deactivate(record: record) == .network)

            let refused = LicenseDeactivationService(
                deactivator: StubDeactivator(result: .failure(.refused("no"))))
            #expect(await refused.deactivate(record: record) == .refused)
        }

        @Test func serviceRejectsBlankKeysWithoutCallingTheNetwork() async {
            let service = LicenseActivationService(
                validator: UnexpectedValidator(),
                signingKey: Curve25519.Signing.PrivateKey())
            #expect(await service.activate(licenseKey: " \n\t ") == .invalidKey)
        }

        @Test func serviceReportsNotConfiguredWithoutASigningKey() async {
            // A from-source build has no injected key → it cannot mint a token and stays free.
            let service = LicenseActivationService(
                validator: StubValidator(
                    result: .success(
                        LicenseActivation(licenseID: "x", instanceID: "i", status: "active"))),
                signingKey: nil)
            #expect(await service.activate(licenseKey: "KEY") == .notConfigured)
        }

        @Test func servicePropagatesValidatorFailures() async {
            let key = Curve25519.Signing.PrivateKey()
            let invalid = LicenseActivationService(
                validator: StubValidator(result: .failure(.invalidKey)), signingKey: key)
            #expect(await invalid.activate(licenseKey: "BAD") == .invalidKey)

            let offline = LicenseActivationService(
                validator: StubValidator(result: .failure(.network("offline"))), signingKey: key)
            #expect(await offline.activate(licenseKey: "KEY") == .network)

            // A server-supplied refusal maps to `.invalidKey`; the refusal message is
            // external text and must not change the outcome (it is logged as a typed
            // reason + length only, never at `.public`).
            let refused = LicenseActivationService(
                validator: StubValidator(result: .failure(.server("Anything the server says"))),
                signingKey: key)
            #expect(await refused.activate(licenseKey: "KEY") == .invalidKey)
        }

        // MARK: - Build-injected signing key

        @Test func signingKeyParsesAValidValueAndRejectsTheRest() {
            // The "free unless injected" guarantee: only a real base64 raw key yields a signer;
            // a missing, empty, unexpanded-placeholder, or garbage value is nil (a free build).
            let real = Curve25519.Signing.PrivateKey()
            let validBase64 = real.rawRepresentation.base64EncodedString()
            #expect(
                LicenseSigningKey.key(fromBase64: validBase64)?.rawRepresentation
                    == real.rawRepresentation)
            #expect(
                LicenseSigningKey.key(fromBase64: " \n\(validBase64)\t")?.rawRepresentation
                    == real.rawRepresentation)
            #expect(LicenseSigningKey.key(fromBase64: nil) == nil)
            #expect(LicenseSigningKey.key(fromBase64: "") == nil)
            #expect(LicenseSigningKey.key(fromBase64: "$(VITRINE_LICENSE_SIGNING_KEY)") == nil)
            #expect(LicenseSigningKey.key(fromBase64: "not-base64!!") == nil)
            // Well-formed base64 of the wrong length is not a valid Ed25519 key → nil.
            #expect(
                LicenseSigningKey.key(fromBase64: Data([1, 2, 3]).base64EncodedString()) == nil)
        }

        // MARK: - CLI token file

        @Test func cliTokenFileWritesThenRemoves() throws {
            let url = tempTokenURL()
            let file = CLITokenFile(url: url)
            file.write("a-token")
            #expect(try String(contentsOf: url, encoding: .utf8) == "a-token")
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(permissions.intValue & 0o777 == 0o600)
            file.write(nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }

        @Test func paywallMasksTheLicenseCredential() throws {
            let source = try String(
                contentsOf: Self.repositoryRoot
                    .appendingPathComponent("Vitrine/Pro/ProGate.swift"),
                encoding: .utf8)
            #expect(source.contains(#"SecureField("Enter your license key""#))
            #expect(!source.contains(#"TextField("Enter your license key""#))
        }

        // MARK: - End-to-end: activation → CLI verdict

        @Test func activationFlowsThroughToTheCLIVerifier() async throws {
            // One dev keypair end to end: activate → the provider persists the token and mirrors
            // it to the CLI file → the CLI's own out-of-process check verifies that file against
            // the matching public key and agrees. Deactivation re-locks both.
            let key = Curve25519.Signing.PrivateKey()
            let verifier = LicenseVerifier(publicKey: key.publicKey)
            let tokenURL = tempTokenURL()
            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(),
                activationRecordStore: InMemoryActivationRecordStore(),
                verifier: verifier,
                cliTokenFile: CLITokenFile(url: tokenURL))
            let service = LicenseActivationService(
                validator: StubValidator(
                    result: .success(
                        LicenseActivation(licenseID: "E2E", instanceID: "i", status: "active"))),
                signingKey: key,
                now: { Date(timeIntervalSince1970: 1_700_000_000) })

            guard
                case .activated(let token, let record) =
                    await service.activate(licenseKey: "KEY")
            else {
                Issue.record("expected activation")
                return
            }
            #expect(provider.setActivation(signedToken: token, record: record))
            #expect(provider.cachedIsPro)
            // The CLI's check, pointed at the written file + the dev key, unlocks — with the env
            // bypass empty so it is the signature that grants PRO, not the Debug override.
            #expect(
                CLIEntitlement.isProUnlocked(
                    tokenURL: tokenURL, verifier: verifier, environment: [:]))

            #expect(provider.clearActivation(ifMatching: record) == .cleared)
            #expect(
                !CLIEntitlement.isProUnlocked(
                    tokenURL: tokenURL, verifier: verifier, environment: [:]))
        }

        private static var repositoryRoot: URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
    }
#endif
