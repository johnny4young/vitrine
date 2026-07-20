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

        /// An in-memory token store so the provider round-trip never touches the real Keychain.
        final class InMemoryTokenStore: LicenseTokenStore {
            private var token: String?
            func read() -> String? { token }
            func write(_ token: String?) { self.token = token }
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
                 "license_key":{"id":42,"status":"active"},
                 "instance":{"id":"inst-1","name":"Mac"}}
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
                                "created_at":"2026-01-01T00:00:00.000000Z","test_mode":true},
                 "meta":{"store_id":1,"product_id":1,"product_name":"Vitrine PRO"}}
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

        // MARK: - Activation service (local minting)

        @Test func serviceMintsAVerifiableTokenOnSuccess() async throws {
            let key = Curve25519.Signing.PrivateKey()
            let service = LicenseActivationService(
                validator: StubValidator(
                    result: .success(
                        LicenseActivation(licenseID: "ORD-9", instanceID: "i", status: "active"))),
                signingKey: key,
                now: { Date(timeIntervalSince1970: 1_700_000_000) })
            guard case .activated(let token) = await service.activate(licenseKey: " KEY ") else {
                Issue.record("expected .activated")
                return
            }
            // The minted token verifies against the matching public key and carries the id.
            #expect(LicenseVerifier(publicKey: key.publicKey).verify(token)?.licenseID == "ORD-9")
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
            file.write(nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
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
                store: InMemoryTokenStore(), verifier: verifier,
                cliTokenFile: CLITokenFile(url: tokenURL))
            let service = LicenseActivationService(
                validator: StubValidator(
                    result: .success(
                        LicenseActivation(licenseID: "E2E", instanceID: "i", status: "active"))),
                signingKey: key,
                now: { Date(timeIntervalSince1970: 1_700_000_000) })

            guard case .activated(let token) = await service.activate(licenseKey: "KEY") else {
                Issue.record("expected activation")
                return
            }
            provider.setToken(token)
            #expect(provider.cachedIsPro)
            // The CLI's check, pointed at the written file + the dev key, unlocks — with the env
            // bypass empty so it is the signature that grants PRO, not the Debug override.
            #expect(
                CLIEntitlement.isProUnlocked(
                    tokenURL: tokenURL, verifier: verifier, environment: [:]))

            provider.setToken(nil)
            #expect(
                !CLIEntitlement.isProUnlocked(
                    tokenURL: tokenURL, verifier: verifier, environment: [:]))
        }
    }
#endif
