import CryptoKit
import Foundation

#if VITRINE_DIRECT_DOWNLOAD
    /// One-time online license activation for the direct-download build (CS-090).
    ///
    /// Flow (Architecture B — the app signs locally): the user pastes a Lemon Squeezy license
    /// key → `LicenseActivationService` validates it once against the Lemon Squeezy License API
    /// → on success the app mints its **own** `LicenseToken`, signs it with a private key
    /// **injected at build time** (`LicenseSigningKey.embedded`), and hands the signed token to
    /// the `LicenseKeyProvider` (which persists it to the Keychain and writes the CLI's shared
    /// token file). Every later check — relaunch and the `vitrine` CLI — verifies that token
    /// **offline** against the embedded public key, so the runtime gate never touches the
    /// network again and is provider-independent.
    ///
    /// Honor/convenience model, not anti-fork DRM: a build compiled from source without the
    /// injected signing key (`LicenseSigningKey.embedded == nil`) simply cannot mint a token,
    /// so it stays free — exactly the "free unless the release private key is injected"
    /// posture. The signature only stops a hand-edited token and lets the CLI trust the app's
    /// activation offline.

    /// The bits a successful Lemon Squeezy activation yields that the app needs to mint a token
    /// and to later re-validate or deactivate the seat.
    struct LicenseActivation: Equatable {
        /// The license identifier (Lemon Squeezy license-key id), carried into the token so a
        /// stored token is traceable to its purchase. Never a secret.
        let licenseID: String
        /// The activation *instance* id Lemon Squeezy returns, needed to deactivate or
        /// re-validate this specific seat later.
        let instanceID: String
        /// The license status as Lemon Squeezy reports it (e.g. `active`).
        let status: String
    }

    /// A typed activation failure, so the paywall can tell "wrong key" from "no internet"
    /// instead of one generic message.
    enum LicenseActivationError: Error, Equatable {
        /// Lemon Squeezy rejected the key (unknown, disabled, or refunded).
        case invalidKey
        /// The key is valid but already activated on its maximum number of machines.
        case activationLimitReached
        /// The request never reached a verdict (transport, timeout, or an undecodable body).
        case network(String)
        /// Lemon Squeezy returned an explicit error message.
        case server(String)
    }

    /// Validates a license key against a provider (Lemon Squeezy in production, a fake in
    /// tests). Abstracted so `LicenseActivationService` is unit-testable without the network.
    protocol LicenseKeyValidator: Sendable {
        /// Activates `licenseKey` for a named instance (the user's machine), returning the
        /// activation details or throwing a `LicenseActivationError`.
        func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation
    }

    /// The production validator: a thin client for the Lemon Squeezy License API
    /// (`POST /v1/licenses/activate`). The license key is itself the credential, so no Lemon
    /// Squeezy API secret is embedded in the app. Response parsing is a pure, testable
    /// function (`parse(status:data:)`) exercised with canned payloads.
    nonisolated struct LemonSqueezyValidator: LicenseKeyValidator {
        /// The activation endpoint. Overridable so a test or a self-host can repoint it.
        var endpoint = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
        /// The session used for the one activation request.
        var session: URLSession = .shared

        func activate(
            licenseKey: String, instanceName: String
        ) async throws -> LicenseActivation {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = Self.formBody([
                "license_key": licenseKey, "instance_name": instanceName,
            ])
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw LicenseActivationError.network(error.localizedDescription)
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return try Self.parse(status: status, data: data)
        }

        /// Form-url-encodes a flat string dictionary for the request body.
        static func formBody(_ fields: [String: String]) -> Data {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let pairs = fields.map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            return pairs.sorted().joined(separator: "&").data(using: .utf8) ?? Data()
        }

        /// Maps a Lemon Squeezy activation response to a `LicenseActivation` or a typed error.
        /// Pure and `nonisolated` so tests can drive it with canned bytes off the main actor.
        nonisolated static func parse(status: Int, data: Data) throws -> LicenseActivation {
            guard let decoded = try? JSONDecoder().decode(LSActivateResponse.self, from: data)
            else {
                throw LicenseActivationError.network("Unreadable response (HTTP \(status)).")
            }
            guard decoded.activated, let instance = decoded.instance else {
                let message = decoded.error ?? "Activation was refused."
                if message.localizedCaseInsensitiveContains("limit") {
                    throw LicenseActivationError.activationLimitReached
                }
                // A 4xx with a key-not-found / inactive verdict is an invalid key; any other
                // explicit message surfaces as a server error so the user sees the reason.
                if status == 404 || decoded.licenseKey?.status == "inactive" {
                    throw LicenseActivationError.invalidKey
                }
                throw decoded.error == nil
                    ? LicenseActivationError.invalidKey
                    : LicenseActivationError.server(message)
            }
            return LicenseActivation(
                licenseID: decoded.licenseKey?.id.map(String.init) ?? "",
                instanceID: instance.id,
                status: decoded.licenseKey?.status ?? "active")
        }

        /// The subset of the Lemon Squeezy activation response the app reads.
        private struct LSActivateResponse: Decodable {
            let activated: Bool
            let error: String?
            let licenseKey: LSLicenseKey?
            let instance: LSInstance?

            struct LSLicenseKey: Decodable {
                let id: Int?
                let status: String?
            }
            struct LSInstance: Decodable { let id: String }

            enum CodingKeys: String, CodingKey {
                case activated, error, instance
                case licenseKey = "license_key"
            }
        }
    }

    /// The outcome of an activation attempt, surfaced to the UI.
    enum ActivationOutcome: Equatable {
        /// Activated; carries the locally-signed token to persist.
        case activated(signedToken: String)
        /// Lemon Squeezy rejected the key.
        case invalidKey
        /// The key is valid but its activation limit is reached.
        case activationLimitReached
        /// Couldn't reach a verdict (offline / transport).
        case network
        /// This build has no embedded signing key, so it can't mint a token — it is a free
        /// build by construction (the real key is injected only into the official release).
        case notConfigured

        /// Whether PRO should now be unlocked.
        var didActivate: Bool { if case .activated = self { true } else { false } }
    }

    /// Orchestrates activation: validate against the provider → mint a locally-signed
    /// `LicenseToken` → return it for persistence. The validator and signing key are injected
    /// so the whole flow is unit-tested with a fake validator and a development key, never the
    /// network or the production key.
    @MainActor
    struct LicenseActivationService {
        let validator: LicenseKeyValidator
        /// The build-injected signing key, or `nil` on a from-source build (→ `notConfigured`).
        let signingKey: Curve25519.Signing.PrivateKey?
        /// The instance name shown in the Lemon Squeezy dashboard for this seat.
        var instanceName: String = LicenseActivationService.defaultInstanceName
        /// Injectable clock so the minted token's `issuedAt` is deterministic under test.
        var now: () -> Date = { Date() }

        /// Validates `licenseKey`, and on success mints and signs a token locally.
        func activate(licenseKey: String) async -> ActivationOutcome {
            guard let signingKey else { return .notConfigured }
            let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                let activation = try await validator.activate(
                    licenseKey: key, instanceName: instanceName)
                let token = LicenseToken(licenseID: activation.licenseID, issuedAt: now())
                let signed = try LicenseSigner.sign(token, with: signingKey)
                return .activated(signedToken: signed)
            } catch LicenseActivationError.invalidKey {
                return .invalidKey
            } catch LicenseActivationError.activationLimitReached {
                return .activationLimitReached
            } catch let LicenseActivationError.server(message) {
                Log.settings.error("License activation refused: \(message, privacy: .public)")
                return .invalidKey
            } catch {
                return .network
            }
        }

        /// A human-readable seat name for the Lemon Squeezy dashboard: the Mac's name, so a
        /// user can recognize and deactivate a seat. Falls back to the product name.
        static var defaultInstanceName: String {
            let name = Host.current().localizedName ?? ""
            return name.isEmpty ? "Vitrine" : name
        }
    }

    /// The public Lemon Squeezy checkout for Vitrine PRO, opened by the paywall's
    /// purchase button. Direct-download only; the App Store build unlocks through
    /// StoreKit instead. The early-bird price is set on the product in Lemon Squeezy
    /// (no discount code), so the link carries no query parameters.
    enum LemonSqueezyStore {
        /// Checkout for the one-time PRO license.
        static let checkoutURL = URL(
            string: "https://johnny4young.lemonsqueezy.com/checkout/buy/"
                + "314e7d43-efa1-41be-a319-7474628e5185"
        )!
    }
#endif
