import SwiftUI

/// Everything that defines the final image. This is the single source of truth
/// shared by the editor preview, the quick-capture path, and the exporter.
struct SnapshotConfig: Equatable {
    var code: String = ""
    var language: Language = .swift
    var theme: Theme = .oneDark
    var fontName: String = "JetBrains Mono"
    var fontSize: Double = 14

    /// Render programming ligatures (e.g. `->`, `=>`, `!=`) for ligature-capable
    /// fonts such as Fira Code or JetBrains Mono (CS-052). Off by default so the
    /// signature look shows discrete glyphs; flipping it on is purely a glyph-level
    /// change and never reflows the code.
    var fontLigatures: Bool = false
    var padding: Double = 32
    var background: BackgroundStyle = .gradient(.aurora)
    var showChrome: Bool = true
    var showShadow: Bool = true
    var cornerRadius: Double = Brand.Radius.card
    var shadowRadius: Double = Brand.Shadow.elevated.radius

    /// Draw a line-number gutter beside the code, in both preview and export
    /// (CS-021). Off by default so the signature look is unchanged.
    var showLineNumbers: Bool = false

    /// Selected 1-based, inclusive line ranges to highlight, e.g. `[3...3, 7...9]`
    /// (CS-021). Empty by default (no highlight). Kept normalized (sorted, merged)
    /// by the settings control via `LineHighlight`, but the renderer tolerates any
    /// ordering.
    var highlightedLineRanges: [ClosedRange<Int>] = []

    /// Optional header context — filename, title, caption, and a language badge
    /// (CS-022). Empty by default, so the header is omitted and the signature look
    /// is unchanged until the user adds context.
    var metadata = SnapshotMetadata()

    /// The shadow radius to draw, honoring the `showShadow` toggle (CS-006).
    var effectiveShadowRadius: Double { showShadow ? shadowRadius : 0 }

    /// Whether the row-by-row code layout (gutter and/or highlight bands) is
    /// active. When neither feature is on, the canvas keeps drawing the code as a
    /// single `Text`, so the default render is byte-for-byte unchanged (CS-021).
    var usesLineRows: Bool { showLineNumbers || !highlightedLineRanges.isEmpty }
}
