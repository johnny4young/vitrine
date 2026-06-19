import AppKit
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

    /// Optional text shown centered in the window-chrome bar (e.g. `ContentView.swift`),
    /// like ray.so / Snappify. Empty by default, so the default chrome (dots only) and
    /// every golden render are unchanged until the user types a title.
    var windowTitle: String = ""

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

    /// Dim the non-highlighted lines so the highlighted ones stand out — the "focus"
    /// mode (CS-021). Off by default, and has no effect without a highlight, so the
    /// default render is unchanged.
    var focusHighlightedLines: Bool = false

    /// Paint added (`+`) lines green and removed (`-`) lines red, GitHub-style, for
    /// diffs. Off by default so the default render is unchanged; when on it switches
    /// to the row layout to band each changed line.
    var diffDecorations: Bool = false

    /// Freeform marks drawn over the snapshot — arrows, text callouts, and
    /// blur/redaction boxes (CS-083). Empty by default, so the default render and
    /// every golden are unchanged until the user adds one. Stored in normalized
    /// canvas coordinates so a mark maps identically across every canvas size.
    var annotations: [Annotation] = []

    /// Optional header context — filename, title, caption, and a language badge
    /// (CS-022). Empty by default, so the header is omitted and the signature look
    /// is unchanged until the user adds context.
    var metadata = SnapshotMetadata()

    /// An optional brand watermark composited onto the exported image — the PRO
    /// Brand Kit (CS-092). `nil` by default, so the default render and every golden
    /// are byte-for-byte unchanged; the canvas only adds the overlay when a
    /// watermark is present. It is *derived* presentation, never part of the saved
    /// style: it is resolved from the app-global brand kit at the export/preview
    /// seam (`AppSettings.exportConfig`) and is never persisted into the document or
    /// fed to the golden suite, exactly like `annotations` leaves the default path
    /// untouched.
    var watermark: Watermark?

    /// The shadow radius to draw, honoring the `showShadow` toggle (CS-006).
    var effectiveShadowRadius: Double { showShadow ? shadowRadius : 0 }

    /// Whether the row-by-row code layout (gutter, highlight bands, and/or diff
    /// bands) is active. When none of these are on, the canvas keeps drawing the code
    /// as a single `Text`, so the default render is byte-for-byte unchanged (CS-021).
    var usesLineRows: Bool {
        showLineNumbers || !highlightedLineRanges.isEmpty || diffDecorations
    }

    /// Clears the marks that are tied to *this specific code* — free-form annotations
    /// (arrows / text / blur) and highlighted line ranges — so loading new content
    /// (paste, drop, quick capture) starts clean instead of stranding marks that were
    /// positioned over unrelated code. Style (theme, font, background, header text)
    /// is reusable and intentionally kept.
    mutating func clearContentMarks() {
        annotations = []
        highlightedLineRanges = []
    }
}

/// A brand watermark composited onto an exported snapshot — the render-ready form
/// of the PRO Brand Kit (CS-092).
///
/// It is deliberately **self-contained**: it carries the resolved logo bytes plus
/// an optional predecoded image (not a store reference) and a plain tint, so
/// `SnapshotCanvas` draws it deterministically with no dependency on the brand-kit
/// store, `SnapshotConfig` stays `Equatable`, and the value renders identically on
/// any machine. The store (`BrandKitStore`) is what turns the user's brand kit into
/// this value; the render core only ever consumes it.
struct Watermark: Equatable {
    /// The handle/project line, e.g. `@jane · vitrine`. May be empty when the user
    /// supplied only a logo.
    var text: String

    /// The brand logo's image bytes (any `NSImage`-decodable format), or `nil` for a
    /// text-only mark. Carried inline so the canvas needs no file/store access.
    var logoImageData: Data?

    /// The predecoded logo image, when the brand-kit store could resolve it. This
    /// keeps `WatermarkBadge` from re-decoding `logoImageData` on every SwiftUI body
    /// pass; `logoImageData` remains the portable fallback for tests and hand-built
    /// values.
    var logoImage: NSImage?

    /// A cheap, stable identity for the logo (its content-addressed file name) used by
    /// `==` so a SwiftUI diff of `SnapshotConfig` doesn't byte-compare the whole logo `Data`
    /// on every render (audit P1-Perf-4). `nil` for a text-only or hand-built mark, where
    /// `==` falls back to the bytes.
    var logoIdentity: String?

    /// The accent tint for the text, or `nil` to use the legible default.
    var tint: RGBAColor?

    /// Which corner the mark sits in — or `.free`, where `freePosition` places it.
    var placement: Placement = .bottomTrailing

    /// For `.free` placement: the mark's center as a normalized point in the canvas
    /// (x,y in 0…1). Ignored for the four corner placements. Defaults to the
    /// bottom-right region, so switching to Free starts where the default corner sat.
    var freePosition: CGPoint = CGPoint(x: 0.84, y: 0.9)

    /// Where a watermark is anchored: one of the four corners, or `.free` (placed
    /// anywhere by dragging it in the preview).
    enum Placement: String, CaseIterable, Codable, Sendable {
        case bottomTrailing, bottomLeading, topTrailing, topLeading, free

        /// A human-readable name for the picker.
        var label: String {
            switch self {
            case .bottomTrailing: String(localized: "Bottom right")
            case .bottomLeading: String(localized: "Bottom left")
            case .topTrailing: String(localized: "Top right")
            case .topLeading: String(localized: "Top left")
            case .free: String(localized: "Free")
            }
        }

        /// The SwiftUI alignment used to pin the mark to its corner. `.free` has no
        /// corner anchor (it is positioned by `freePosition`); it returns `.center`
        /// only as an exhaustive fallback.
        var alignment: Alignment {
            switch self {
            case .bottomTrailing: .bottomTrailing
            case .bottomLeading: .bottomLeading
            case .topTrailing: .topTrailing
            case .topLeading: .topLeading
            case .free: .center
            }
        }
    }

    /// Clamps a normalized point into the canvas (each axis in 0…1), used so a free
    /// watermark position can never drift fully off the image.
    static func clampFreePosition(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }

    /// Whether the mark has anything to draw — at least a logo or a non-empty line.
    var hasContent: Bool { logoImageData != nil || !text.isEmpty }

    /// Equality compares the logo by its cheap content identity rather than its bytes, so a
    /// SwiftUI diff of `SnapshotConfig` stays O(1) on every render (audit P1-Perf-4). When
    /// neither side has an identity (a text-only or hand-built mark) it falls back to the
    /// bytes, so correctness is unchanged.
    static func == (lhs: Watermark, rhs: Watermark) -> Bool {
        guard lhs.text == rhs.text, lhs.tint == rhs.tint, lhs.placement == rhs.placement
        else { return false }
        // `freePosition` only changes the render under `.free` placement, so two
        // corner-placed marks that differ only in a stored free position stay equal —
        // this keeps a SwiftUI diff of `SnapshotConfig` from triggering needless
        // rerenders when the position is carried but unused.
        if lhs.placement == .free, lhs.freePosition != rhs.freePosition { return false }
        if lhs.logoIdentity != nil || rhs.logoIdentity != nil {
            return lhs.logoIdentity == rhs.logoIdentity
        }
        return lhs.logoImageData == rhs.logoImageData
    }
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
