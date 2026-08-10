import Foundation
import StoreKit

/// The outcome of a purchase attempt, so the paywall can tell success from a user cancel
/// (silent) and a genuine failure (show an error) instead of clearing the spinner with no
/// signal. Compiled unconditionally so `Entitlements` can return it on every build.
enum PurchaseOutcome: Equatable {
    case unlocked
    case cancelled
    case failed
}

/// The StoreKit operations the entitlement provider needs, separated from the provider's
/// caching and outcome policy so every purchase/restore path can be exercised without an
/// App Store account or an Xcode StoreKit session.
///
/// ``live`` is the only production implementation. Tests inject deterministic closures,
/// while the provider remains responsible for caching, mapping StoreKit states to the
/// paywall's ``PurchaseOutcome``, and owning the transaction-update task.
struct StoreKitClient {
    enum PurchaseResult: Equatable, Sendable {
        /// StoreKit completed the purchase sheet. The provider still re-reads verified
        /// current entitlements before unlocking; an unverified transaction therefore
        /// cannot grant PRO by itself.
        case completed
        case userCancelled
        case pending
        case failed
    }

    let currentIsPro: @MainActor (String) async -> Bool
    let purchase: @MainActor (String) async throws -> PurchaseResult
    let sync: @MainActor () async throws -> Void
    let observeUpdates: @MainActor (@escaping @MainActor () -> Void) -> Task<Void, Never>

    static let live = Self(
        currentIsPro: { productID in
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                if transaction.productID == productID, transaction.revocationDate == nil {
                    return true
                }
            }
            return false
        },
        purchase: { productID in
            guard let product = try await Product.products(for: [productID]).first else {
                return .failed
            }
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                return .completed
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        },
        sync: {
            try await AppStore.sync()
        },
        observeUpdates: { onChange in
            Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    // Replacing or destroying a provider cancels this task. Do not let a
                    // value already delivered by StoreKit notify a stale owner afterward.
                    guard !Task.isCancelled else { return }
                    onChange()
                }
            }
        })
}

/// The App Store entitlement provider: PRO is a single **non-consumable** IAP
/// ("Vitrine PRO", lifetime). It reads `Transaction.currentEntitlements` for the live
/// state, exposes purchase and the required **Restore Purchases**, and can observe
/// `Transaction.updates` for out-of-band changes (a purchase on another device, a refund).
///
/// The type compiles on every build (StoreKit is a system framework, so a built-but-unused
/// provider in the direct-download build is harmless); it is only *selected* on the App
/// Store build, where `Entitlements.defaultProvider()` gates the choice with
/// `#if !VITRINE_DIRECT_DOWNLOAD`. The direct-download build uses the license-key provider
/// instead. Nothing here transmits anything about the purchase beyond StoreKit's own flow —
/// no receipt is sent anywhere, no analytics; a failure logs only the error domain/code,
/// never a receipt, product, or account detail.
///
/// A refunded purchase is revoked (`revocationDate` set), so
/// it drops out of `currentEntitlements` and `isPro` flips to `false` on the next refresh —
/// PRO re-locks, but nothing the user made (exports, presets, brand kit) is destroyed.
@MainActor
final class StoreKitProvider: LiveEntitlementProvider {
    /// The non-consumable product identifier; must match the IAP configured in App Store
    /// Connect ("Vitrine PRO", lifetime).
    static let productID = "com.johnny4young.vitrine.pro"

    private let defaults: UserDefaults
    private let client: StoreKitClient
    private let cacheKey = "proStoreKitCachedIsPro"
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, client: StoreKitClient = .live) {
        self.defaults = defaults
        self.client = client
    }

    isolated deinit {
        updatesTask?.cancel()
    }

    /// The last resolved PRO state, persisted so boot is instant and offline.
    var cachedIsPro: Bool { defaults.bool(forKey: cacheKey) }

    /// Resolves PRO from the current App Store entitlements: `true` when a non-revoked,
    /// verified transaction for the product is present. Caches the result for the next boot.
    func currentIsPro() async -> Bool {
        let unlocked = await client.currentIsPro(Self.productID)
        defaults.set(unlocked, forKey: cacheKey)
        return unlocked
    }

    /// Buys the PRO product and reports the outcome. Errors (no product, network, payment)
    /// surface as `.failed` rather than being swallowed, so the paywall can tell the user
    /// something went wrong instead of silently clearing its spinner. On failure it logs
    /// only the error's domain and code — never a receipt, product, or account detail.
    func purchase() async -> PurchaseOutcome {
        do {
            switch try await client.purchase(Self.productID) {
            case .completed:
                // Never trust a purchase-sheet result directly. Only a verified,
                // non-revoked current entitlement can unlock the cached state.
                return await currentIsPro() ? .unlocked : .failed
            case .userCancelled, .pending:
                return .cancelled
            case .failed:
                return .failed
            }
        } catch {
            // A purchase failure is exactly when a Console trace helps support; log the
            // error domain/code only (non-PII), matching the logging policy.
            let nsError = error as NSError
            Log.settings.error(
                "StoreKit purchase failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))"
            )
            return .failed
        }
    }

    /// Restore Purchases (an App Store requirement): syncs with the App Store, then
    /// re-resolves the entitlement so a clean install re-grants a prior purchase.
    func restore() async -> Bool {
        try? await client.sync()
        return await currentIsPro()
    }

    /// Observes out-of-band transaction updates (a purchase on another device, a refund),
    /// invoking `onChange` so the owner can refresh the entitlement. The task lives for the
    /// provider's lifetime (the app's, for the shared instance).
    func startObservingUpdates(onChange: @escaping @MainActor () -> Void) {
        updatesTask?.cancel()
        updatesTask = client.observeUpdates(onChange)
    }
}
