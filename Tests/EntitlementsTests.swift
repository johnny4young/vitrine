import CryptoKit
import Foundation
import Testing

@testable import Vitrine

/// the PRO entitlement core: provider-backed `isPro`, per-feature unlock, async
/// refresh, and the guardrail that the local Debug unlock can never ship.
@Suite("PRO entitlement core")
@MainActor
struct EntitlementsTests {
    /// The injectable fake the test contract needs: a controllable provider with separate
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

    final class LiveFakeProvider: @MainActor LiveEntitlementProvider {
        var cachedIsPro: Bool
        var liveIsPro: Bool
        private(set) var refreshCount = 0
        private var onChange: (@MainActor () -> Void)?

        init(cached: Bool, live: Bool? = nil) {
            self.cachedIsPro = cached
            self.liveIsPro = live ?? cached
        }

        func currentIsPro() async -> Bool {
            refreshCount += 1
            return liveIsPro
        }

        func startObservingUpdates(onChange: @escaping @MainActor () -> Void) {
            self.onChange = onChange
        }

        func sendUpdate() {
            onChange?()
        }
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

    @Test func liveUpdatesRefreshTheOwningEntitlementGraph() async {
        let provider = LiveFakeProvider(cached: false)
        let entitlements = Entitlements(provider: provider)

        entitlements.startLiveUpdates()
        #expect(await eventually { provider.refreshCount == 1 })
        #expect(!entitlements.isPro)

        provider.liveIsPro = true
        provider.sendUpdate()

        #expect(await eventually { entitlements.isPro })
        #expect(provider.refreshCount == 2)
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

    /// Guardrail: the local PRO unlock must be Debug-only so it can never ship.
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

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            await Task.yield()
        }
        return predicate()
    }
}

/// The App Store StoreKit provider. StoreKit itself is still certified with an Xcode
/// `.storekit` configuration before distribution; the injected client keeps the provider's
/// caching, purchase, restore, and observer lifecycle deterministic in the normal suite.
@Suite("StoreKit PRO provider")
@MainActor
struct StoreKitProviderTests {
    private final class ClientSpy {
        struct FixtureError: Error {}

        var currentResults: [Bool] = []
        var purchaseResult: StoreKitClient.PurchaseResult = .failed
        var purchaseError: Error?
        var syncError: Error?

        var currentProductIDs: [String] = []
        var purchaseProductIDs: [String] = []
        var syncCount = 0
        var updateHandlers: [@MainActor () -> Void] = []
        var updateTasks: [Task<Void, Never>] = []

        var client: StoreKitClient {
            StoreKitClient(
                currentIsPro: { productID in
                    self.currentProductIDs.append(productID)
                    return self.currentResults.isEmpty ? false : self.currentResults.removeFirst()
                },
                purchase: { productID in
                    self.purchaseProductIDs.append(productID)
                    if let purchaseError = self.purchaseError { throw purchaseError }
                    return self.purchaseResult
                },
                sync: {
                    self.syncCount += 1
                    if let syncError = self.syncError { throw syncError }
                },
                observeUpdates: { handler in
                    self.updateHandlers.append(handler)
                    let task = Task<Void, Never> {
                        try? await Task.sleep(for: .seconds(60))
                    }
                    self.updateTasks.append(task)
                    return task
                })
        }
    }

    @Test func startsFromTheOfflineCacheAndExposesTheConfiguredProduct() {
        let defaults = testDefaults()
        defaults.set(true, forKey: "proStoreKitCachedIsPro")
        let provider = StoreKitProvider(defaults: defaults, client: ClientSpy().client)

        #expect(provider.cachedIsPro)
        #expect(StoreKitProvider.productID == "com.johnny4young.vitrine.pro")
    }

    @Test func currentEntitlementReplacesTheOfflineCache() async {
        let defaults = testDefaults()
        let spy = ClientSpy()
        spy.currentResults = [true, false]
        let provider = StoreKitProvider(defaults: defaults, client: spy.client)

        #expect(await provider.currentIsPro())
        #expect(provider.cachedIsPro)
        #expect(await provider.currentIsPro() == false)
        #expect(!provider.cachedIsPro)
        #expect(spy.currentProductIDs == [StoreKitProvider.productID, StoreKitProvider.productID])
    }

    @Test(arguments: [false, true])
    func completedPurchaseTrustsOnlyTheRefreshedEntitlement(isVerified: Bool) async {
        let spy = ClientSpy()
        spy.purchaseResult = .completed
        spy.currentResults = [isVerified]
        let provider = StoreKitProvider(defaults: testDefaults(), client: spy.client)

        let outcome = await provider.purchase()

        #expect(outcome == (isVerified ? .unlocked : .failed))
        #expect(spy.purchaseProductIDs == [StoreKitProvider.productID])
        #expect(spy.currentProductIDs == [StoreKitProvider.productID])
        #expect(provider.cachedIsPro == isVerified)
    }

    @Test(arguments: [StoreKitClient.PurchaseResult.userCancelled, .pending])
    func cancellationAndPendingStaySilent(
        result: StoreKitClient.PurchaseResult
    ) async {
        let spy = ClientSpy()
        spy.purchaseResult = result
        let provider = StoreKitProvider(defaults: testDefaults(), client: spy.client)

        #expect(await provider.purchase() == .cancelled)
        #expect(spy.currentProductIDs.isEmpty)
    }

    @Test func storeKitFailureAndThrownErrorFailWithoutUnlocking() async {
        let spy = ClientSpy()
        let provider = StoreKitProvider(defaults: testDefaults(), client: spy.client)

        #expect(await provider.purchase() == .failed)
        spy.purchaseError = ClientSpy.FixtureError()
        #expect(await provider.purchase() == .failed)
        #expect(spy.currentProductIDs.isEmpty)
        #expect(!provider.cachedIsPro)
    }

    @Test(arguments: [false, true])
    func restoreRefreshesAfterSyncEvenWhenSyncFails(syncFails: Bool) async {
        let spy = ClientSpy()
        spy.currentResults = [true]
        if syncFails { spy.syncError = ClientSpy.FixtureError() }
        let provider = StoreKitProvider(defaults: testDefaults(), client: spy.client)

        #expect(await provider.restore())
        #expect(spy.syncCount == 1)
        #expect(spy.currentProductIDs == [StoreKitProvider.productID])
        #expect(provider.cachedIsPro)
    }

    @Test func replacingTheUpdateObserverCancelsTheOldTask() async throws {
        let spy = ClientSpy()
        let provider = StoreKitProvider(defaults: testDefaults(), client: spy.client)
        var firstChanges = 0
        var secondChanges = 0

        provider.startObservingUpdates { firstChanges += 1 }
        let firstTask = try #require(spy.updateTasks.first)
        provider.startObservingUpdates { secondChanges += 1 }

        #expect(firstTask.isCancelled)
        #expect(spy.updateTasks.count == 2)
        #expect(spy.updateHandlers.count == 2)
        spy.updateHandlers[1]()
        #expect(firstChanges == 0)
        #expect(secondChanges == 1)
    }

    @Test func releasingTheProviderCancelsItsUpdateObserver() throws {
        let spy = ClientSpy()
        var provider: StoreKitProvider? = StoreKitProvider(
            defaults: testDefaults(), client: spy.client)
        weak let releasedProvider = provider
        provider?.startObservingUpdates {}
        let task = try #require(spy.updateTasks.first)

        provider = nil

        #expect(releasedProvider == nil)
        #expect(task.isCancelled)
    }
}

/// the direct-download license-key provider: offline Ed25519 token verification,
/// tamper rejection, and the local activate/deactivate round-trip. The external published-DMG
/// activation journey is certified separately by the release QA runbook; these pin the offline
/// crypto the CLI also relies on.
@Suite("License key PRO provider")
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
        // forged or hand-edited token cannot unlock PRO. Only a token the
        // app minted with the matching, build-injected private key verifies.
        let foreignKey = Curve25519.Signing.PrivateKey()
        let token = try LicenseSigner.sign(
            LicenseToken(
                licenseID: "FOREIGN", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            with: foreignKey)
        #expect(LicenseVerifier.embedded.verify(token) == nil)
    }

    @Test func embeddedPublicKeyIsThePinnedProductionKey() {
        // The embedded verifier must be the fixed production public key: silent key
        // drift would lock out paying users because their
        // real-key-signed tokens would stop verifying), so pin the exact bytes here.
        // Update this literal only alongside a deliberate key rotation.
        #expect(
            LicenseVerifier.embedded.publicKey.rawRepresentation.base64EncodedString()
                == "GBiLsURlP+jwJGvfAJUAxTACaZbObIVBnBurkOQ+Fd0=")
    }

    #if VITRINE_DIRECT_DOWNLOAD
        /// An in-memory token store so the provider round-trip is tested without touching the
        /// real Keychain (the Keychain store itself is exercised manually).
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
