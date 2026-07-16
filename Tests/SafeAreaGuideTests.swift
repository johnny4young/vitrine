import CoreGraphics
import Testing

@testable import Vitrine

/// Feature #20 — the editor-only safe-area guide: the crop-margin rect and the live
/// line/column budget are pure math, pinned here; the overlay never touches the export
/// (`SnapshotCanvas` has no knowledge of it, so no render test is needed or wanted).
@Suite("Safe-area guide")
struct SafeAreaGuideTests {
    @Test func guideRectInsetsByFivePercentOfTheShorterSide() {
        // 1200×630 (OpenGraph): shorter side 630 → inset round(31.5) = 32.
        let rect = SafeAreaGuide.guideRect(for: CGSize(width: 1200, height: 630))
        #expect(rect == CGRect(x: 32, y: 32, width: 1200 - 64, height: 630 - 64))
    }

    @Test func guideRectUsesTheShorterSideForBothAxes() {
        // A tall story (1080×1920): the inset comes from the width, not the height,
        // so a wide margin never eats a banner's short axis.
        let rect = SafeAreaGuide.guideRect(for: CGSize(width: 1080, height: 1920))
        #expect(rect.minX == 54)
        #expect(rect.minY == 54)
    }

    @Test func guideRectDegeneratesSafely() {
        #expect(SafeAreaGuide.guideRect(for: .zero) == .zero)
        #expect(SafeAreaGuide.guideRect(for: CGSize(width: -10, height: 5)) == .zero)
    }

    @Test func budgetCountsLinesAndWidestColumn() {
        let (lines, columns) = SafeAreaGuide.budget(for: "let x = 1\nprint(x, x, x)\nok")
        #expect(lines == 3)
        #expect(columns == "print(x, x, x)".count)
    }

    @Test func budgetOfEmptyCodeIsZero() {
        let (lines, columns) = SafeAreaGuide.budget(for: "")
        #expect(lines == 0)
        #expect(columns == 0)
    }
}

extension SafeAreaGuideTests {
    /// The inspector toggle and the stage overlay observe the same defaults key via
    /// one shared constant; this pins the constant's value so a rename can't silently
    /// disconnect persisted toggles (deep-review test gap).
    @Test func guideToggleStorageKeyIsStable() {
        #expect(SafeAreaGuide.storageKey == "editorShowsSafeAreaGuides")
    }
}
