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

    #if DEBUG && VITRINE_DIRECT_DOWNLOAD
        @Test func managedLicenseUIFixtureRequiresExplicitIsolation() {
            #expect(
                ManagedLicenseUITestFixture.makeEntitlements(environment: [:]) == nil)
            #expect(
                ManagedLicenseUITestFixture.makeEntitlements(
                    environment: [
                        ManagedLicenseUITestFixture.environmentKey: "1"
                    ]) == nil)
            #expect(
                ManagedLicenseUITestFixture.makeEntitlements(
                    environment: ["VITRINE_USER_DEFAULTS_SUITE": "isolated"]) == nil)
            #expect(
                ManagedLicenseUITestFixture.makeEntitlements(
                    environment: [
                        ManagedLicenseUITestFixture.environmentKey: "1",
                        "VITRINE_USER_DEFAULTS_SUITE": "   ",
                    ]) == nil)
        }

        @Test func managedLicenseUIFixtureRelocksThroughTheDefaultService() async {
            let entitlements = Entitlements.makeDefault(
                environment: [
                    ManagedLicenseUITestFixture.environmentKey: "1",
                    "VITRINE_USER_DEFAULTS_SUITE": "isolated-managed-license-test",
                ])

            #expect(entitlements.isPro)
            #expect(entitlements.directLicenseManagementState == .active)
            #expect(await entitlements.deactivateLicense() == .deactivated)
            #expect(!entitlements.isPro)
            #expect(entitlements.directLicenseManagementState == .unavailable)
        }

        @Test func managedLicenseUIFixtureCannotDriftIntoProductionOrRealCredentials() throws {
            let fixture = try String(
                contentsOf: Self.repoFile(
                    "Vitrine", "Pro", "ManagedLicenseUITestFixture.swift"),
                encoding: .utf8)
            let environmentRoot = try String(
                contentsOf: Self.repoFile("Vitrine", "App", "AppEnvironment.swift"),
                encoding: .utf8)
            let uiTests = try String(
                contentsOf: Self.repoFile("UITests", "VitrineUITests.swift"), encoding: .utf8)

            #expect(fixture.hasPrefix("#if DEBUG && VITRINE_DIRECT_DOWNLOAD"))
            #expect(fixture.contains("VITRINE_MANAGED_LICENSE_UI_TEST"))
            #expect(fixture.contains("VITRINE_USER_DEFAULTS_SUITE"))
            #expect(fixture.contains("KeychainLicenseStore") == false)
            #expect(fixture.contains("KeychainLicenseActivationRecordStore") == false)
            #expect(fixture.contains("LemonSqueezyValidator()") == false)
            #expect(fixture.contains("URLSession") == false)
            #expect(environmentRoot.contains("entitlements ?? Entitlements.makeDefault()"))
            #expect(uiTests.contains("VITRINE_MANAGED_LICENSE_UI_TEST"))
        }
    #endif

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
            private(set) var token: String?
            var rejectsClear = false

            init(token: String? = nil) {
                self.token = token
            }

            func read() -> String? { token }
            func write(_ token: String?) -> Bool {
                if token == nil, rejectsClear { return false }
                self.token = token
                return true
            }
        }

        final class InMemoryActivationRecordStore: LicenseActivationRecordStore {
            private(set) var record: LicenseActivationRecord?
            var rejectsClear = false

            init(record: LicenseActivationRecord? = nil) {
                self.record = record
            }

            func read() -> LicenseActivationRecord? { record }
            func write(_ record: LicenseActivationRecord?) -> Bool {
                if record == nil, rejectsClear { return false }
                self.record = record
                return true
            }
        }

        nonisolated struct StubDeactivator: LicenseKeyDeactivator {
            let result: Result<LicenseDeactivation, LicenseDeactivationError>

            func deactivate(
                licenseKey: String, instanceID: String
            ) async throws -> LicenseDeactivation {
                try result.get()
            }
        }

        actor RecordingValidator: LicenseKeyValidator {
            private(set) var callCount = 0
            let result: Result<LicenseActivation, LicenseActivationError>

            init(result: Result<LicenseActivation, LicenseActivationError>) {
                self.result = result
            }

            func activate(
                licenseKey: String, instanceName: String
            ) async throws -> LicenseActivation {
                callCount += 1
                return try result.get()
            }
        }

        actor ControlledDeactivator: LicenseKeyDeactivator {
            private var didStart = false
            private var startWaiter: CheckedContinuation<Void, Never>?
            private var response: CheckedContinuation<LicenseDeactivation, Error>?

            func deactivate(
                licenseKey: String, instanceID: String
            ) async throws -> LicenseDeactivation {
                didStart = true
                startWaiter?.resume()
                startWaiter = nil
                return try await withCheckedThrowingContinuation { continuation in
                    response = continuation
                }
            }

            func waitUntilStarted() async {
                if didStart { return }
                await withCheckedContinuation { continuation in
                    startWaiter = continuation
                }
            }

            func succeed(licenseID: String) {
                response?.resume(returning: LicenseDeactivation(licenseID: licenseID))
                response = nil
            }
        }

        @Test func providerUnlocksWithAValidTokenAndClearsOnDeactivation() throws {
            let key = Curve25519.Signing.PrivateKey()
            let recordStore = InMemoryActivationRecordStore()
            let cliTokenURL = tempTokenURL()
            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(),
                activationRecordStore: recordStore,
                verifier: LicenseVerifier(publicKey: key.publicKey),
                cliTokenFile: CLITokenFile(url: cliTokenURL))
            #expect(!provider.cachedIsPro)
            let token = try LicenseSigner.sign(
                LicenseToken(licenseID: "L1", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
                with: key)
            let record = try #require(
                LicenseActivationRecord(
                    licenseKey: "KEY", licenseID: "L1", instanceID: "instance-1"))
            #expect(provider.setActivation(signedToken: token, record: record))
            #expect(provider.cachedIsPro)
            #expect(provider.activationRecordForDeactivation == record)
            #expect(FileManager.default.fileExists(atPath: cliTokenURL.path))
            #expect(provider.clearActivation(ifMatching: record) == .cleared)
            #expect(!provider.cachedIsPro)
            #expect(recordStore.record == nil)
            #expect(!FileManager.default.fileExists(atPath: cliTokenURL.path))
        }

        @Test func providerRejectsATokenFromAnotherLicense() throws {
            let key = Curve25519.Signing.PrivateKey()
            let recordStore = InMemoryActivationRecordStore()
            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(),
                activationRecordStore: recordStore,
                verifier: LicenseVerifier(publicKey: key.publicKey),
                cliTokenFile: CLITokenFile(url: tempTokenURL()))
            let token = try LicenseSigner.sign(
                LicenseToken(licenseID: "OTHER", issuedAt: .now), with: key)
            let record = try #require(
                LicenseActivationRecord(
                    licenseKey: "KEY", licenseID: "L1", instanceID: "instance-1"))

            #expect(!provider.setActivation(signedToken: token, record: record))
            #expect(!provider.cachedIsPro)
            #expect(recordStore.record == nil)
        }

        @Test func recoverableSeatRecordCannotBeOverwrittenOrConsumeAnotherSeat() async throws {
            let key = Curve25519.Signing.PrivateKey()
            let oldRecord = try #require(
                LicenseActivationRecord(
                    licenseKey: "OLD-KEY", licenseID: "OLD", instanceID: "old-instance"))
            let recordStore = InMemoryActivationRecordStore(record: oldRecord)
            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(),
                activationRecordStore: recordStore,
                verifier: LicenseVerifier(publicKey: key.publicKey),
                cliTokenFile: CLITokenFile(url: tempTokenURL()))
            let entitlements = Entitlements(provider: provider)
            let validator = RecordingValidator(
                result: .success(
                    LicenseActivation(
                        licenseID: "NEW", instanceID: "new-instance", status: "active")))
            let service = LicenseActivationService(
                validator: validator,
                signingKey: key)

            #expect(!entitlements.isPro)
            #expect(entitlements.directLicenseManagementState == .cleanupNeeded)
            let activationSucceeded = await entitlements.activate(
                licenseKey: "NEW-KEY", using: service)
            #expect(!activationSucceeded)
            #expect(await validator.callCount == 0)
            #expect(provider.activationRecordForDeactivation == oldRecord)

            let newToken = try LicenseSigner.sign(
                LicenseToken(licenseID: "NEW", issuedAt: .now), with: key)
            let newRecord = try #require(
                LicenseActivationRecord(
                    licenseKey: "NEW-KEY", licenseID: "NEW", instanceID: "new-instance"))
            #expect(!provider.setActivation(signedToken: newToken, record: newRecord))
            #expect(provider.activationRecordForDeactivation == oldRecord)
        }

        @Test func legacyTokenRemainsProWithoutInventingASeatRecord() async throws {
            let key = Curve25519.Signing.PrivateKey()
            let token = try LicenseSigner.sign(
                LicenseToken(licenseID: "LEGACY", issuedAt: .now), with: key)
            let provider = LicenseKeyProvider(
                store: InMemoryTokenStore(token: token),
                activationRecordStore: InMemoryActivationRecordStore(),
                verifier: LicenseVerifier(publicKey: key.publicKey),
                cliTokenFile: CLITokenFile(url: tempTokenURL()))
            let entitlements = Entitlements(provider: provider)

            #expect(entitlements.isPro)
            #expect(provider.hasLegacyActivation)
            #expect(entitlements.directLicenseManagementState == .legacy)
            #expect(
                await entitlements.deactivateLicense(
                    using: LicenseDeactivationService(
                        deactivator: StubDeactivator(
                            result: .success(LicenseDeactivation(licenseID: "LEGACY")))))
                    == .notActivated)
            #expect(entitlements.isPro)
        }

        @Test(arguments: [
            LicenseDeactivationError.network("offline"),
            .refused("provider refusal"),
        ])
        func inconclusiveDeactivationPreservesEveryLocalCredential(
            failure: LicenseDeactivationError
        ) async throws {
            let fixture = try activeFixture(licenseID: "L1")
            let entitlements = Entitlements(provider: fixture.provider)

            let outcome = await entitlements.deactivateLicense(
                using: LicenseDeactivationService(
                    deactivator: StubDeactivator(result: .failure(failure))))

            #expect(outcome == (failure == .network("offline") ? .network : .refused))
            #expect(entitlements.isPro)
            #expect(fixture.provider.activationRecordForDeactivation == fixture.record)
            #expect(FileManager.default.fileExists(atPath: fixture.cliTokenURL.path))
        }

        @Test(arguments: [false, true])
        func conclusiveDeactivationRelocksAppAndCLI(alreadyInactive: Bool) async throws {
            let fixture = try activeFixture(licenseID: "L1")
            let entitlements = Entitlements(provider: fixture.provider)
            let result: Result<LicenseDeactivation, LicenseDeactivationError> =
                alreadyInactive
                ? .failure(.alreadyInactive)
                : .success(LicenseDeactivation(licenseID: "L1"))

            let outcome = await entitlements.deactivateLicense(
                using: LicenseDeactivationService(
                    deactivator: StubDeactivator(result: result)))

            #expect(outcome == (alreadyInactive ? .alreadyInactive : .deactivated))
            #expect(!entitlements.isPro)
            #expect(fixture.provider.activationRecordForDeactivation == nil)
            #expect(!FileManager.default.fileExists(atPath: fixture.cliTokenURL.path))
        }

        @Test func localCleanupFailurePreservesARecoverableRecord() async throws {
            let fixture = try activeFixture(licenseID: "L1")
            fixture.tokenStore.rejectsClear = true
            let entitlements = Entitlements(provider: fixture.provider)

            let outcome = await entitlements.deactivateLicense(
                using: LicenseDeactivationService(
                    deactivator: StubDeactivator(
                        result: .success(LicenseDeactivation(licenseID: "L1")))))

            #expect(outcome == .localCleanupFailed)
            #expect(entitlements.isPro)
            #expect(fixture.provider.activationRecordForDeactivation == fixture.record)
            #expect(FileManager.default.fileExists(atPath: fixture.cliTokenURL.path))
        }

        @Test func suspendedDeactivationCannotClearANewerActivation() async throws {
            let fixture = try activeFixture(licenseID: "OLD")
            let entitlements = Entitlements(provider: fixture.provider)
            let controlled = ControlledDeactivator()
            let task = Task {
                await entitlements.deactivateLicense(
                    using: LicenseDeactivationService(deactivator: controlled))
            }
            await controlled.waitUntilStarted()

            let key = fixture.key
            let newToken = try LicenseSigner.sign(
                LicenseToken(licenseID: "NEW", issuedAt: .now), with: key)
            let newRecord = try #require(
                LicenseActivationRecord(
                    licenseKey: "NEW-KEY", licenseID: "NEW", instanceID: "new-instance"))
            // Simulate an out-of-band recovery removing the old record while its request is
            // suspended. The provider can then accept a genuinely newer activation, and the
            // stale response must still compare-and-refuse rather than clearing it.
            #expect(fixture.recordStore.write(nil))
            #expect(
                fixture.provider.setActivation(
                    signedToken: newToken,
                    record: newRecord))

            await controlled.succeed(licenseID: "OLD")
            #expect(await task.value == .superseded)
            #expect(fixture.provider.cachedIsPro)
            #expect(fixture.provider.activationRecordForDeactivation == newRecord)
        }

        @Test func aboutPaneUsesAConfirmingCancellableLicenseJourney() throws {
            let root = try String(
                contentsOf: Self.repoFile("Vitrine", "Settings", "SettingsRootView.swift"),
                encoding: .utf8)
            let about = try String(
                contentsOf: Self.repoFile("Vitrine", "Settings", "AboutSettingsView.swift"),
                encoding: .utf8)
            #expect(root.contains("entitlements: environment.entitlements"))
            #expect(about.contains(".confirmationDialog("))
            #expect(about.contains(".task(id: deactivationRequestID)"))
            #expect(about.contains("deactivate-license-button"))
            #expect(about.contains("SecureField") == false)
        }

        private struct ActiveFixture {
            let key: Curve25519.Signing.PrivateKey
            let tokenStore: InMemoryTokenStore
            let recordStore: InMemoryActivationRecordStore
            let provider: LicenseKeyProvider
            let record: LicenseActivationRecord
            let cliTokenURL: URL
        }

        private func activeFixture(licenseID: String) throws -> ActiveFixture {
            let key = Curve25519.Signing.PrivateKey()
            let tokenStore = InMemoryTokenStore()
            let recordStore = InMemoryActivationRecordStore()
            let cliTokenURL = tempTokenURL()
            let provider = LicenseKeyProvider(
                store: tokenStore,
                activationRecordStore: recordStore,
                verifier: LicenseVerifier(publicKey: key.publicKey),
                cliTokenFile: CLITokenFile(url: cliTokenURL))
            let token = try LicenseSigner.sign(
                LicenseToken(licenseID: licenseID, issuedAt: .now), with: key)
            let record = try #require(
                LicenseActivationRecord(
                    licenseKey: "KEY-\(licenseID)",
                    licenseID: licenseID,
                    instanceID: "instance-\(licenseID)"))
            #expect(provider.setActivation(signedToken: token, record: record))
            return ActiveFixture(
                key: key,
                tokenStore: tokenStore,
                recordStore: recordStore,
                provider: provider,
                record: record,
                cliTokenURL: cliTokenURL)
        }

        private func tempTokenURL() -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("vitrine-provider-test-\(UUID().uuidString)")
                .appendingPathComponent("pro-license.token", isDirectory: false)
        }

        private static func repoFile(_ components: String...) -> URL {
            components.reduce(
                URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
            ) { $0.appendingPathComponent($1) }
        }
    #endif
}
