import CoreGraphics
import Foundation

/// The editor-only safe-area guide for a fixed-size destination: the
/// margin platforms tend to cover with their own UI (avatars, action bars, crop
/// rounding), plus the live line/column budget of the code being framed.
///
/// Pure math so it is unit-testable; the stage draws it as a dashed overlay that never
/// reaches the export (`SnapshotCanvas` knows nothing about it).
enum SafeAreaGuide {
    /// The defaults key behind the guide toggle. One constant shared by the two
    /// `@AppStorage` declarations (inspector toggle, stage overlay) so a typo in
    /// either can no longer silently disconnect them.
    static let storageKey = "editorShowsSafeAreaGuides"

    /// The fraction of the shorter canvas side treated as at-risk margin. 5% is the
    /// conservative envelope of the common feed crops (X, LinkedIn, OpenGraph
    /// previews round or overlay within ~4–5% of the edge).
    static let marginFraction: CGFloat = 0.05

    /// The guide rectangle for a canvas of `size`: the area content should stay
    /// inside to survive platform crops/overlays. The inset derives from the shorter
    /// side so wide banners don't get an exaggerated vertical margin.
    static func guideRect(for size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let inset = (min(size.width, size.height) * marginFraction).rounded()
        return CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    }

    /// The live content budget: how many lines the snippet spans and its widest
    /// column (in characters), the two numbers that decide whether code stays
    /// legible at a feed's display size. Tabs count as one column, matching the
    /// editor's monospaced layout of what was actually typed.
    static func budget(for code: String) -> (lines: Int, columns: Int) {
        guard !code.isEmpty else { return (0, 0) }
        let lines = code.components(separatedBy: "\n")
        return (lines.count, lines.map(\.count).max() ?? 0)
    }
}
