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
    /// Between the cacheable size and the highlighting ceiling, the LRU caches refuse the
    /// document by design — but every consumer in one settle asks for the same text, and
    /// each was re-highlighting it: the editor for its attributed string, the preview for
    /// the bridged one, the gutter for its rows. Keeping the most recent value costs one
    /// document regardless of how wide that band is, which is what makes it safe.
    @Test func mediumSourceReusesItsMostRecentDerivedValues() throws {
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        let source = String(repeating: "let value = compute(42)\n", count: 3_000)
        #expect(!HighlightPolicy.shouldCache(source))
        #expect(HighlightPolicy.mode(for: source, language: .swift) == .full)

        let attributed = manager.attributedString(
            for: source, language: .swift, theme: .oneDark, font: Self.font)
        let bridged = manager.swiftUIAttributedString(
            for: source, language: .swift, theme: .oneDark, font: Self.font)
        let rows = manager.swiftUIAttributedLines(
            for: source, language: .swift, theme: .oneDark, font: Self.font)

        #expect(attributed.string == source)
        #expect(String(bridged.characters) == source)
        #expect(rows.count == source.components(separatedBy: "\n").count)
        // One retained value per representation, and nothing more: three documents' worth
        // of derived state would be exactly what the size limit exists to prevent.
        #expect(manager.cachedEntryCountForTesting == 3)

        // A different document replaces them rather than accumulating, and reads its own
        // value — the bound and the correctness are the same assertion.
        let other = source + "let different = true\n"
        let otherAttributed = manager.attributedString(
            for: other, language: .swift, theme: .oneDark, font: Self.font)
        #expect(otherAttributed.string == other)
        #expect(manager.cachedEntryCountForTesting == 3)
    }

    /// A terminal capture is the one input with no size ceiling: source code falls back to
    /// plain text past a documented limit, while a capture goes through the full parser,
    /// emulator, and per-run styling at any size the file loader accepts. Above the
    /// cacheable size the canvas and the gutter were each paying that in full — the gutter
    /// re-rendered the frame before splitting it — so one settle did the work twice.
    @Test func largeTerminalCaptureReusesItsMostRecentFrame() {
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        let row = "\u{1B}[32m✓\u{1B}[0m \u{1B}[1mpassed\u{1B}[0m"
        let capture = (0..<3_000).map { "\(row) line \($0)" }.joined(separator: "\n")
        #expect(!HighlightPolicy.shouldCache(capture))

        let frame = manager.terminalAttributedString(
            for: capture, theme: .oneDark, font: Self.font, columns: nil)
        let rows = manager.terminalAttributedLines(
            for: capture, theme: .oneDark, font: Self.font, columns: nil)

        // The rows are the frame's own lines, not a second render of the capture.
        #expect(rows.count == 3_000)
        #expect(String(frame.characters).contains("line 2999"))
        #expect(manager.cachedEntryCountForTesting == 2)

        // A different capture replaces both rather than accumulating.
        let other = capture + "\n\(row) line 3000"
        _ = manager.terminalAttributedString(
            for: other, theme: .oneDark, font: Self.font, columns: nil)
        #expect(manager.cachedEntryCountForTesting == 2)
    }

    /// The terminal path had no ceiling: source code stops being tokenized past a
    /// documented size, but a capture was parsed, emulated, and styled run by run at any
    /// size the file loader accepts — five megabytes. Its own, larger ceiling bounds that
    /// while leaving room for a recorded session or a piped build log.
    @Test func terminalCapturesCarryTheirOwnLargerCeiling() {
        #expect(
            HighlightPolicy.maximumTerminalByteCount
                > HighlightPolicy.maximumHighlightedByteCount)

        let row = "\u{1B}[32m✓\u{1B}[0m ok"
        func capture(bytes: Int) -> String {
            var rows: [String] = []
            var size = 0
            var index = 0
            while size < bytes {
                let line = "\(row) line \(index)"
                rows.append(line)
                size += line.utf8.count + 1
                index += 1
            }
            return rows.joined(separator: "\n")
        }

        let under = capture(bytes: HighlightPolicy.maximumTerminalByteCount / 2)
        let over = capture(bytes: HighlightPolicy.maximumTerminalByteCount * 2)
        #expect(HighlightPolicy.mode(for: under, language: .terminal) == .full)
        #expect(HighlightPolicy.mode(for: over, language: .terminal).usesPlainTextFallback)

        // Source keeps its own, smaller ceiling: a capture that is still colored would
        // already be plain text as source.
        #expect(HighlightPolicy.mode(for: under, language: .swift).usesPlainTextFallback)
    }

    /// Above the ceiling the capture must stay *readable*, not merely uncolored. The
    /// escapes are resolved away by the same renderer that would have styled them, so a
    /// line redraw still collapses instead of leaving every frame it ever drew.
    @Test func aCaptureAboveTheCeilingKeepsItsTextAndDropsItsEscapes() {
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        var rows: [String] = []
        var size = 0
        var index = 0
        while size < HighlightPolicy.maximumTerminalByteCount * 2 {
            let line = "\u{1B}[32m✓\u{1B}[0m \u{1B}[1mstep\u{1B}[0m \(index)"
            rows.append(line)
            size += line.utf8.count + 1
            index += 1
        }
        // A carriage-return redraw, the case a naive escape-stripper would get wrong.
        rows.append("progress 10%\rprogress 100%")
        let capture = rows.joined(separator: "\n")

        let rendered = manager.terminalAttributedString(
            for: capture, theme: .oneDark, font: Self.font, columns: nil)
        let text = String(rendered.characters)

        #expect(!text.contains("\u{1B}"), "no escape sequence may survive into the text")
        #expect(text.contains("✓ step 0"))
        #expect(text.contains("progress 100%"))
        #expect(!text.contains("progress 10%\rprogress"), "a redraw must still collapse")
    }

}
