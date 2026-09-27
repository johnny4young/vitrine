#if DEBUG
    import Foundation

    /// An opt-in, isolated StoreKit UI graph. No App Store account, receipt, transaction,
    /// credential, or network is touched. The price is synthetic test data, not an offer.
    /// Both Debug channels compile this graph for provider tests; only the Store
    /// channel's app entry point can select it through the environment.
    enum ManagedStoreUITestFixture {
        static let environmentKey = "VITRINE_MANAGED_STORE_UI_TEST"

        enum Scenario: String {
            case priceAvailable = "price-available"
            case priceRetry = "price-retry"
            case priceUnavailable = "price-unavailable"
        }

        static func makeEntitlements(
            environment: [String: String], defaults: UserDefaults = AppDefaults.current
        ) -> Entitlements? {
            guard let scenario = environment[environmentKey].flatMap(Scenario.init(rawValue:)),
                let suite = environment["VITRINE_USER_DEFAULTS_SUITE"],
                !suite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            var priceRequests = 0
            var unlocked = false
            let client = StoreKitClient(
                displayPrice: { _ in
                    priceRequests += 1
                    switch scenario {
                    case .priceAvailable: return "12,34 €"
                    case .priceRetry: return priceRequests > 1 ? "12,34 €" : nil
                    case .priceUnavailable: return nil
                    }
                },
                currentIsPro: { _ in unlocked },
                purchase: { _ in .userCancelled },
                sync: { unlocked = true },
                observeUpdates: { _ in Task {} })
            return Entitlements(provider: StoreKitProvider(defaults: defaults, client: client))
        }
    }
#endif
