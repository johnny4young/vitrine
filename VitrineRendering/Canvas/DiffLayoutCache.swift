import Foundation
import VitrineDomain

/// Parsed diffs, their hunks and gutter labels keyed by code, so the inspector, the canvas and
/// style-only changes share one parse per edit.
public final class DiffLayoutCache {
    struct GutterKey: Hashable {
        var code: String
        var numbering: DiffLineNumbers
        var firstLineNumber: Int
        var redactions: [ClosedRange<Int>]
    }

    public static let shared = DiffLayoutCache()

    private var documents = CostLimitedLRUCache<String, (DiffDocument, [DiffHunk])>(
        totalCostLimit: 32 * 1_024 * 1_024, countLimit: 4)
    private var gutters = CostLimitedLRUCache<GutterKey, (labels: [String], columns: Int)>(
        totalCostLimit: 32 * 1_024 * 1_024, countLimit: 4)
    private(set) var misses = 0

    public func document(for code: String) -> DiffDocument { entry(for: code).0 }

    public func hunks(in code: String) -> [DiffHunk] { entry(for: code).1 }

    func gutterLabels(
        _ numbering: DiffLineNumbers, code: String, firstLineNumber: Int,
        redacting redactions: [ClosedRange<Int>]
    ) -> (labels: [String], columns: Int) {
        let normalized = LineHighlight.normalize(redactions)
        let key = GutterKey(
            code: code, numbering: numbering, firstLineNumber: firstLineNumber,
            redactions: normalized)
        if let cached = gutters.value(forKey: key) { return cached }
        let labels = document(for: code).gutterLabels(
            numbering, firstLineNumber: firstLineNumber, redacting: normalized)
        gutters.insert(labels, forKey: key, cost: code.utf8.count + labels.labels.count * 16)
        return labels
    }

    private func entry(for code: String) -> (DiffDocument, [DiffHunk]) {
        if let cached = documents.value(forKey: code) { return cached }
        misses += 1
        let document = DiffDocument(source: code)
        let entry = (document, document.hunks)
        documents.insert(entry, forKey: code, cost: code.utf8.count * 2)
        return entry
    }
}
