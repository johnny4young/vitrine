import Foundation
import VitrineDomain

/// Word marks keyed by what they depend on, so a style-only change (theme, font, padding, a
/// slider tick) reuses the last result instead of rerunning the per-line diff.
final class DiffWordMarksCache {
    struct Key: Hashable {
        var code: String
        var redactions: [ClosedRange<Int>]

        init(config: SnapshotConfig) {
            code = config.code
            redactions = LineHighlight.normalize(config.redactedLineRanges)
        }
    }

    static let shared = DiffWordMarksCache()

    private var cache = CostLimitedLRUCache<Key, [Int: [Range<Int>]]>(
        totalCostLimit: 32 * 1_024 * 1_024, countLimit: 4)
    private(set) var misses = 0

    func marks(for key: Key, compute: () -> [Int: [Range<Int>]]) -> [Int: [Range<Int>]] {
        if let cached = cache.value(forKey: key) { return cached }
        misses += 1
        let marks = compute()
        cache.insert(marks, forKey: key, cost: key.code.utf8.count + marks.count * 64)
        return marks
    }
}
