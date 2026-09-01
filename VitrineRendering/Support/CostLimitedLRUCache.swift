import Foundation
import VitrineDomain

/// A deterministic least-recently-used cache bounded by both item count and estimated cost.
///
/// `NSCache` is appropriate for opportunistic caches, but its eviction order is intentionally
/// unspecified. Highlighting benefits from deterministic recency because a user commonly toggles
/// between a small number of themes and documents. This value type keeps that contract explicit
/// while still treating values as disposable: callers provide a conservative byte-cost estimate,
/// and an entry larger than the entire budget is never retained.
struct CostLimitedLRUCache<Key: Hashable, Value> {
    struct Metrics: Equatable {
        let count: Int
        let totalCost: Int
    }

    private struct Entry {
        var value: Value
        var cost: Int
    }

    let totalCostLimit: Int
    let countLimit: Int

    private var entries: [Key: Entry] = [:]
    /// Oldest at the front, newest at the back. Highlight caches hold only a handful of entries,
    /// so this compact representation avoids reference-node ownership and stays cheap to audit.
    private var recency: [Key] = []
    private(set) var totalCost = 0

    init(totalCostLimit: Int, countLimit: Int) {
        precondition(totalCostLimit >= 0)
        precondition(countLimit >= 0)
        self.totalCostLimit = totalCostLimit
        self.countLimit = countLimit
    }

    var metrics: Metrics { Metrics(count: entries.count, totalCost: totalCost) }

    mutating func value(forKey key: Key) -> Value? {
        guard let entry = entries[key] else { return nil }
        touch(key)
        return entry.value
    }

    /// Inserts `value` as the newest entry. Invalid or over-budget costs are treated as a request
    /// not to cache; an older value under the same key is removed so stale output cannot survive.
    mutating func insert(_ value: Value, forKey key: Key, cost: Int) {
        removeValue(forKey: key)
        guard countLimit > 0, cost >= 0, cost <= totalCostLimit else { return }

        // Make room before adding so even an intentionally extreme generic budget cannot
        // overflow `totalCost`. The production highlight caches use much smaller limits, but the
        // container itself should keep its arithmetic contract for every valid initializer.
        while entries.count >= countLimit || totalCost > totalCostLimit - cost {
            guard let oldest = recency.first else { return }
            removeValue(forKey: oldest)
        }
        entries[key] = Entry(value: value, cost: cost)
        recency.append(key)
        totalCost += cost
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        entries.removeAll(keepingCapacity: keepingCapacity)
        recency.removeAll(keepingCapacity: keepingCapacity)
        totalCost = 0
    }

    private mutating func touch(_ key: Key) {
        guard let index = recency.firstIndex(of: key) else { return }
        recency.remove(at: index)
        recency.append(key)
    }

    private mutating func removeValue(forKey key: Key) {
        if let removed = entries.removeValue(forKey: key) {
            totalCost -= removed.cost
        }
        if let index = recency.firstIndex(of: key) {
            recency.remove(at: index)
        }
    }
}
