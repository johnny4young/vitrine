import AppKit
import Testing
import VitrineDomain

@testable import VitrineRendering

@MainActor
@Suite("Cost-limited LRU cache")
struct CostLimitedLRUCacheTests {
    @Test func evictsTheLeastRecentlyUsedEntryByCost() {
        var cache = CostLimitedLRUCache<String, Int>(totalCostLimit: 10, countLimit: 3)
        cache.insert(1, forKey: "a", cost: 3)
        cache.insert(2, forKey: "b", cost: 3)
        #expect(cache.value(forKey: "a") == 1)  // a is now newer than b

        cache.insert(3, forKey: "c", cost: 5)

        #expect(cache.value(forKey: "b") == nil)
        #expect(cache.value(forKey: "a") == 1)
        #expect(cache.value(forKey: "c") == 3)
        #expect(cache.metrics == .init(count: 2, totalCost: 8))
    }

    @Test func replacingAKeyUpdatesCostWithoutDuplicatingRecency() {
        var cache = CostLimitedLRUCache<String, Int>(totalCostLimit: 10, countLimit: 2)
        cache.insert(1, forKey: "same", cost: 8)
        cache.insert(2, forKey: "same", cost: 2)
        cache.insert(3, forKey: "other", cost: 7)

        #expect(cache.value(forKey: "same") == 2)
        #expect(cache.value(forKey: "other") == 3)
        #expect(cache.metrics == .init(count: 2, totalCost: 9))
    }

    @Test func anEntryLargerThanTheBudgetIsNeverRetained() {
        var cache = CostLimitedLRUCache<String, Int>(totalCostLimit: 10, countLimit: 2)
        cache.insert(1, forKey: "key", cost: 5)
        cache.insert(2, forKey: "key", cost: 11)

        #expect(cache.value(forKey: "key") == nil)
        #expect(cache.metrics == .init(count: 0, totalCost: 0))
    }

    @Test func insertionCannotOverflowAnExtremeTotalCostBudget() {
        var cache = CostLimitedLRUCache<String, Int>(totalCostLimit: .max, countLimit: 2)
        cache.insert(1, forKey: "old", cost: Int.max - 1)

        cache.insert(2, forKey: "new", cost: 2)

        #expect(cache.value(forKey: "old") == nil)
        #expect(cache.value(forKey: "new") == 2)
        #expect(cache.metrics == .init(count: 1, totalCost: 2))
    }
}

@MainActor
@Suite("Highlight memory and large-document policy")
struct HighlightPolicyTests {
    private static let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    @Test func byteBoundariesChooseFullOrPlainTextModeExactly() {
        let atLimit = String(repeating: "a", count: HighlightPolicy.maximumHighlightedByteCount)
        let overLimit = atLimit + "a"

        #expect(HighlightPolicy.mode(for: atLimit, language: .swift) == .full)
        #expect(
            HighlightPolicy.mode(for: overLimit, language: .swift)
                == .plainTextFallback(
                    actualBytes: HighlightPolicy.maximumHighlightedByteCount + 1,
                    maximumBytes: HighlightPolicy.maximumHighlightedByteCount))
    }

    @Test func policyCountsUTF8BytesRatherThanCharacters() {
        let scalar = "🧪"
        let count = HighlightPolicy.maximumHighlightedByteCount / scalar.utf8.count + 1
        let unicode = String(repeating: scalar, count: count)

        #expect(unicode.count < HighlightPolicy.maximumHighlightedByteCount)
        #expect(
            HighlightPolicy.mode(for: unicode, language: .swift).usesPlainTextFallback)
    }

    @Test func mediumDocumentsBypassCachesAndUseALongerDebounce() {
        let medium = String(
            repeating: "let value = 42\n",
            count: HighlightPolicy.maximumCacheableByteCount / 15 + 2)
        #expect(!HighlightPolicy.shouldCache(medium))
        #expect(HighlightPolicy.mode(for: medium, language: .swift) == .full)
        #expect(
            HighlightPolicy.editorDebounce(for: medium)
                > HighlightPolicy.editorDebounce(for: "let value = 42"))
    }

    @Test func largeSourceFallsBackLegiblyWithoutEnteringDerivedCaches() throws {
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        let source = String(
            repeating: "let value = 42\n",
            count: HighlightPolicy.maximumHighlightedByteCount / 15 + 2)

        let attributed = manager.attributedString(
            for: source, language: .swift, theme: .oneDark, font: Self.font)

        #expect(attributed.string == source)
        #expect(manager.cachedEntryCountForTesting == 0)
        let foreground = try #require(
            attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(foreground.alphaComponent > 0)
    }

    @Test func screenshotSizedSourcePopulatesBoundedDerivedCaches() {
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        let source = "func greet() { print(\"hello\") }"

        _ = manager.swiftUIAttributedLines(
            for: source, language: .swift, theme: .oneDark, font: Self.font)

        #expect(manager.cachedEntryCountForTesting == 3)
    }
}
