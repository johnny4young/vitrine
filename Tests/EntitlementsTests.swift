import CryptoKit
import Foundation
import Testing

@testable import Vitrine

/// CS-088 — the PRO entitlement core: provider-backed `isPro`, per-feature unlock, async
/// refresh, and the guardrail that the local Debug unlock can never ship.
@Suite("PRO entitlement core · CS-088")
@MainActor
struct EntitlementsTests {
    /// The injectable fake the ticket calls for: a controllable provider with separate
    /// cached (boot) and live (refresh) values.
    final class FakeProvider: EntitlementProvider {
        var cachedIsPro: Bool
        var liveIsPro: Bool
        init(cached: Bool, live: Bool? = nil) {
            self.cachedIsPro = cached
            self.liveIsPro = live ?? cached
        }
        func currentIsPro() async -> Bool { liveIsPro }
    }

    @Test func bootSeedsIsProFromTheCachedFlag() {
        #expect(Entitlements(provider: FakeProvider(cached: true)).isPro)
        #expect(!Entitlements(provider: FakeProvider(cached: false)).isPro)
    }

    @Test func everyFeatureFollowsTheProFlag() {
        let pro = Entitlements(provider: FakeProvider(cached: true))
        let free = Entitlements(provider: FakeProvider(cached: false))
        for feature in ProFeature.allCases {
            #expect(pro.isUnlocked(feature))
            #expect(!free.isUnlocked(feature))
        }
    }

    @Test func refreshPublishesTheLiveProviderValue() async {
        let entitlements = Entitlements(provider: FakeProvider(cached: false, live: true))
        #expect(!entitlements.isPro)  // seeded from the cached flag at boot
        await entitlements.refresh()
        #expect(entitlements.isPro)  // updated to the live value
    }

    @Test func theFreeProviderLocksEverything() async {
        let entitlements = Entitlements(provider: FreeProvider())
        #expect(!entitlements.isPro)
        await entitlements.refresh()
        #expect(!entitlements.isPro)
    }

    @Test func everyFeatureHasNonEmptyPaywallCopy() {
        for feature in ProFeature.allCases {
            #expect(!feature.paywallTitle.isEmpty)
            #expect(!feature.paywallBlurb.isEmpty)
        }
    }

    /// Guardrail (CS-088): the local PRO unlock must be Debug-only so it can never ship.
    /// Source-scan the entitlement file to prove `DebugUnlockProvider` is wrapped in a
    /// `#if DEBUG` block — a release compile therefore contains no unlock path at all.
    @Test func debugUnlockProviderIsCompiledOutOfRelease() throws {
        let source = try String(
            contentsOf: Self.repoFile("Vitrine", "Pro", "Entitlements.swift"), encoding: .utf8)
        let lines = source.components(separatedBy: "\n")
        let declIndex = try #require(
            lines.firstIndex { $0.contains("struct DebugUnlockProvider") },
            "DebugUnlockProvider should be present in the source")
        let nearestConditional = lines[..<declIndex].last {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if")
        }
        #expect(
            nearestConditional?.contains("#if DEBUG") == true,
            "DebugUnlockProvider must be inside #if DEBUG so it never ships in a release build")
    }

    private static func repoFile(_ components: String...) -> URL {
        components.reduce(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // repo root
        ) { $0.appendingPathComponent($1) }
    }
}

/// CS-089 — the App Store StoreKit provider. The live purchase/restore/refund flow is
/// validated manually with an Xcode `.storekit` configuration (it needs StoreKit's test
/// environment); this pins the deterministic, runtime-free guarantees.
@Suite("StoreKit PRO provider · CS-089")
@MainActor
struct StoreKitProviderTests {
    @Test func startsFreeAndExposesTheConfiguredProduct() {
        let provider = StoreKitProvider(
            defaults: UserDefaults(suiteName: "VitrineStoreKit-\(UUID().uuidString)")!)
        // No purchase recorded → free at boot, and the product id matches the App Store
        // Connect IAP the provider queries.
        #expect(!provider.cachedIsPro)
        #expect(StoreKitProvider.productID == "com.johnny4young.vitrine.pro")
    }
}

/// CS-090 — the direct-download license-key provider: offline Ed25519 token verification,
/// tamper rejection, and the activate/deactivate round-trip. Real Lemon Squeezy activation
/// is deferred (it needs the LS account); these pin the offline crypto the CLI also relies on.
@Suite("License key PRO provider · CS-090")
@MainActor
struct LicenseKeyTests {
    @Test func aMintedTokenVerifiesAndTamperingIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let token = try LicenseSigner.sign(
            LicenseToken(
                licenseID: "ABC-123", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            with: key)
        #expect(verifier.verify(token)?.licenseID == "ABC-123")
        // A tampered token and a token signed by a different key are both refused.
        #expect(verifier.verify("tampered." + token) == nil)
        let wrongKey = LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey)
        #expect(wrongKey.verify(token) == nil)
    }

    @Test func embeddedVerifierRejectsForeignTokens() throws {
        // No foreign-signed token validates against the embedded production public key, so a
        // forged or hand-edited token cannot unlock PRO (audit P1-Security-6). Only a token the
        // app minted with the matching, build-injected private key verifies.
        let foreignKey = Curve25519.Signing.PrivateKey()
        let token = try LicenseSigner.sign(
            LicenseToken(
                licenseID: "FOREIGN", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            with: foreignKey)
        #expect(LicenseVerifier.embedded.verify(token) == nil)
    }

    @Test func embeddedPublicKeyIsThePinnedProductionKey() {
        // The embedded verifier must be the fixed production public key (audit
        // P1-Security-6): a silent key drift would lock out paying users (their
        // real-key-signed tokens would stop verifying), so pin the exact bytes here.
        // Update this literal only alongside a deliberate key rotation.
        #expect(
            LicenseVerifier.embedded.publicKey.rawRepresentation.base64EncodedString()
                == "GBiLsURlP+jwJGvfAJUAxTACaZbObIVBnBurkOQ+Fd0=")
    }

    #if VITRINE_DIRECT_DOWNLOAD
        /// An in-memory token store so the provider round-trip is tested without touching the
        /// real Keychain (CS-090; the Keychain store itself is exercised manually).
        final class InMemoryTokenStore: LicenseTokenStore {
            private var token: String?
            func read() -> String? { token }
            func write(_ token: String?) { self.token = token }
        }

        @Test func providerUnlocksWithAValidTokenAndClearsOnDeactivation() throws {
            let key = Curve25519.Signing.PrivateKey()
            // Inject a temp CLI-token file so `setToken` does not write the real container path.
            let cliTokenURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitrine-provider-test-\(UUID().uuidString)")
                .appendingPathComponent("pro-license.token", isDirectory: false)
            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(),
                verifier: LicenseVerifier(publicKey: key.publicKey),
                cliTokenFile: CLITokenFile(url: cliTokenURL))
            #expect(!provider.cachedIsPro)
            let token = try LicenseSigner.sign(
                LicenseToken(licenseID: "L1", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                with: key)
            provider.setToken(token)
            #expect(provider.cachedIsPro)
            provider.setToken(nil)
            #expect(!provider.cachedIsPro)
        }
    #endif
}
