#if DEBUG
    import Foundation

    /// An opt-in, isolated StoreKit UI graph. No App Store account, receipt, transaction,
    /// credential, or network is touched. The price is synthetic test data, not an offer.
    /// Both Debug channels compile this graph for provider tests; only the Store
    /// channel's app entry point can select it through the environment.
    enum ManagedStoreUITestFixture {
        static let environmentKey = "VITRINE_MANAGED_STORE_UI_TEST"

        static func makeEntitlements(
            environment: [String: String], defaults: UserDefaults = AppDefaults.current
        ) -> Entitlements? {
            guard let scenario = environment[environmentKey],
                ["price-available", "price-retry", "price-unavailable"].contains(scenario),
                let suite = environment["VITRINE_USER_DEFAULTS_SUITE"],
                !suite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            var priceRequests = 0
            var unlocked = false
            let client = StoreKitClient(
                displayPrice: { _ in
                    priceRequests += 1
                    guard scenario != "price-unavailable",
                        scenario != "price-retry" || priceRequests > 1
                    else { return nil }
                    return "12,34 €"
                },
                currentIsPro: { _ in unlocked },
                purchase: { _ in .userCancelled },
                sync: { unlocked = true },
                observeUpdates: { _ in Task {} })
            return Entitlements(provider: StoreKitProvider(defaults: defaults, client: client))
        }
    }
#endif
