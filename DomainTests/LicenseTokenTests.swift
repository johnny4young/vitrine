import CryptoKit
import Foundation
import Testing
import VitrineDomain

@Suite("Shared offline license contract")
struct LicenseTokenTests {
    @Test func encodedPayloadAndDecodedValuesStayStable() throws {
        let key = Curve25519.Signing.PrivateKey()
        let value = LicenseToken(
            licenseID: "synthetic-license", issuedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let signed = try LicenseSigner.sign(value, with: key)
        let repeated = try LicenseSigner.sign(value, with: key)
        #expect(repeated.split(separator: ".")[0] == signed.split(separator: ".")[0])
        #expect(LicenseVerifier(publicKey: key.publicKey).verify(repeated) == value)
        let payload = try #require(Data(base64Encoded: String(signed.split(separator: ".")[0])))
        #expect(
            String(decoding: payload, as: UTF8.self)
                == #"{"issuedAt":"2023-11-14T22:13:20Z","licenseID":"synthetic-license"}"#)
        #expect(LicenseVerifier(publicKey: key.publicKey).verify(signed) == value)
        #expect(
            LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey).verify(signed)
                == nil)
        #expect(LicenseVerifier.embedded.verify(signed) == nil)
    }

    @Test(arguments: ["", ".", "invalid", "a.b.c", "e30=.", ".AAAA", "!!!!.AAAA"])
    func malformedTokensFailClosed(_ token: String) {
        let key = Curve25519.Signing.PrivateKey()
        #expect(LicenseVerifier(publicKey: key.publicKey).verify(token) == nil)
        #expect(LicenseVerifier(publicKeyBase64: "invalid").verify(token) == nil)
    }

    @Test func signatureDoesNotAuthorizeMalformedOrCrossedPayloads() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let valid = Data(
            #"{"issuedAt":"2023-11-14T22:13:20Z","licenseID":"synthetic-license"}"#.utf8)
        let other = Data(#"{"issuedAt":"2023-11-14T22:13:20Z","licenseID":"another-license"}"#.utf8)
        let signature = try key.signature(for: valid).base64EncodedString()
        #expect(verifier.verify(other.base64EncodedString() + "." + signature) == nil)
        let malformed = Data(#"{"licenseID":"synthetic-license"}"#.utf8)
        let signedMalformed =
            malformed.base64EncodedString() + "."
            + (try key.signature(for: malformed)).base64EncodedString()
        #expect(verifier.verify(signedMalformed) == nil)
    }
}
