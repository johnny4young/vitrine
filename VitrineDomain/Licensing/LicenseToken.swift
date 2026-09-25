import CryptoKit
import Foundation

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
public struct LicenseToken: Codable, Equatable, Sendable {
    /// The opaque license identifier (e.g. the Lemon Squeezy order/license id) — never a
    /// secret, carried so a token is traceable to its purchase.
    public let licenseID: String
    /// When the token was issued, by the signer's clock. Informational; the gate does not
    /// expire a lifetime license.
    public let issuedAt: Date

    public init(licenseID: String, issuedAt: Date) {
        self.licenseID = licenseID
        self.issuedAt = issuedAt
    }
}

/// Verifies a signed `LicenseToken` offline against an embedded Ed25519 public key.
/// Shared by the app and the CLI so both reach the same verdict from the same token bytes.
public struct LicenseVerifier: Sendable {
    /// The signing public key, or `nil` when an embedded representation is malformed. This
    /// value is safe to ship in source; only the matching private key is secret and injected
    /// into the official direct-download build.
    public let publicKey: Curve25519.Signing.PublicKey?

    public init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// Builds a verifier from shipped configuration. Invalid bytes produce an unconfigured
    /// verifier that rejects every token rather than terminating app or CLI startup.
    public init(publicKeyBase64: String) {
        publicKey = Data(base64Encoded: publicKeyBase64).flatMap {
            try? Curve25519.Signing.PublicKey(rawRepresentation: $0)
        }
    }

    /// Decodes and verifies a `"<base64 payload>.<base64 signature>"` token, returning the
    /// payload only when the signature checks out. Any malformed, tampered, or
    /// wrongly-signed token returns `nil` — never a partial trust.
    public func verify(_ token: String) -> LicenseToken? {
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
    public static let embedded = LicenseVerifier(
        publicKeyBase64: LicensePublicKeys.productionBase64)
}

private enum LicensePublicKeys {
    nonisolated static let productionBase64 = "GBiLsURlP+jwJGvfAJUAxTACaZbObIVBnBurkOQ+Fd0="
}

/// Mints a signed token from a private key. Under embedded-key activation model the **app** runs this
/// at activation, with the build-injected `LicenseSigningKey.embedded`; the same function backs
/// the unit tests' mint → verify → tamper path with a throwaway development key.
public enum LicenseSigner {
    public static func sign(
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
