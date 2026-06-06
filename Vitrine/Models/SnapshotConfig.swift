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

extension SnapshotConfig {
    /// Applies the shared CLI/Shortcuts presentation precedence on top of this base
    /// configuration, so every automation surface frames an image the same way the
    /// GUI does (CS-020/CS-034). This is the single resolver behind both
    /// `CLIOptions.makeConfig` and `SnapshotRenderRequest.makeConfig`, which used to
    /// carry byte-for-byte identical copies of these steps.
    ///
    /// Order of application, lowest precedence first:
    ///   1. This base configuration (factory defaults for the CLI, the user's saved
    ///      style for automation).
    ///   2. The destination preset's presentation guidance (padding/background).
    ///   3. The theme override.
    ///   4. The transparent-background override (wins over a preset's background).
    ///
    /// `code` and `language` are deliberately left untouched: they describe *what* is
    /// rendered, not *how* it is styled, and a preset is presentation/output only
    /// (CS-020). The caller sets them after styling.
    func styled(presetID: String?, themeID: String?, transparent: Bool) -> SnapshotConfig {
        var config = self
        // 2. Preset guidance (padding/background) layered onto the base.
        if let preset = ExportPreset.preset(withID: presetID) {
            preset.apply(to: &config)
        }
        // 3. Theme override — resolved through the custom-theme store so a custom-theme
        // id works and an unknown/built-in id falls back to the built-in catalog,
        // matching the GUI (CS-031).
        if let themeID {
            config.theme = CustomThemeStore.shared.theme(withID: themeID)
        }
        // 4. Transparency is the last word on the background, layering cleanly onto any
        // preset (the caller asked for real alpha regardless, CS-024).
        if transparent {
            config.background = .transparent
        }
        return config
    }
}
