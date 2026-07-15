import CoreGraphics
import Foundation

/// The parsed options for a single `vitrine render` invocation (CS-033).
///
/// `CLIOptions` is the pure, value-typed result of parsing `argv` — it carries no
/// AppKit state and does no rendering, so it can be unit-tested off the main actor
/// and reused by both the executable and the test suite. Building a `SnapshotConfig`
/// from it (`makeConfig()`) is what ties the CLI to the exact same render inputs the
/// GUI uses, so output is pixel-identical to the app for the same options.
///
/// Every field defaults to the app's own default, taken from `SnapshotConfig()`,
/// `SettingsDefaults`, and `ColorProfile.fallback`, so a bare `vitrine render
/// input.swift --out image.png` renders what the editor would render with untouched
/// settings (CS-033 "CLI defaults match app defaults unless overridden").
///
/// Main-actor isolated (the module default) so `makeConfig` can build a
/// `SnapshotConfig` and apply the main-actor `ExportPreset`/`Theme`/`SettingsDefaults`
/// model exactly as the GUI does, keeping the produced image identical.
@MainActor
struct CLIOptions: Equatable {
    /// Whether this is a single-file `render` or a folder `batch` (CS-094). For
    /// `batch`, `inputPath`/`outputPath` are directories rather than files; every
    /// style flag still applies per rendered file.
    var command: Command = .render

    /// The CLI subcommand. `render` writes one image; `batch` renders every text file
    /// in a folder into an output folder (CS-094).
    enum Command: String, Equatable, Sendable { case render, batch }

    /// Whether `inputPath` names source text or a local image to beautify. Image input
    /// is render-only and is copied into an invocation-scoped temporary store, never
    /// the app's persistent foreground-image library.
    enum InputKind: String, Equatable, Sendable { case code, image }

    /// Suppresses the success summary on stdout. Errors and explicit skipped-file
    /// diagnostics still go to stderr so automation logs stay actionable.
    var quiet: Bool = false
    /// Prints the success summary as JSON for scripts that need structured stdout.
    /// Errors remain human-readable stderr, matching the rest of the CLI contract.
    var jsonOutput: Bool = false

    /// The kind of file carried by `inputPath`. Defaults to code so existing render
    /// and batch invocations keep their original behavior.
    var inputKind: InputKind = .code

    /// The source file to read (a folder for `batch`). Code language is inferred from
    /// its extension/content; image input is decoded locally and never persisted.
    var inputPath: String
    /// Where the rendered image is written (an output folder for `batch`).
    var outputPath: String

    /// An explicit syntax theme id (e.g. `dracula`), or `nil` to use the default
    /// theme. Resolved through the built-in catalog; an unknown id is rejected up
    /// front rather than silently degraded, so a typo in a docs pipeline fails loud.
    var themeID: String?
    /// An explicit language override (e.g. `swift`), or `nil` to infer from the
    /// file extension / content.
    var language: Language?
    /// An explicit destination preset id (e.g. `opengraph`), or `nil` for no preset.
    /// A preset reframes presentation/output exactly as it does in the GUI and never
    /// touches the source (CS-020).
    var presetID: String?
    /// The export resolution multiplier (1/2/3). When a preset is chosen and no
    /// explicit scale is given, the preset's recommended scale is used, mirroring the
    /// GUI's "preset seeds the scale, an explicit value overrides it" rule (CS-020).
    var scale: Int?
    /// Optional code font family override. Resolved through `CodeFont.all` so the CLI
    /// accepts the same bundled/system programming fonts as the editor.
    var fontName: String?
    /// Optional programming-ligature override for fonts that support them. Nil preserves
    /// the app/preset default; a value maps to the editor's ligature toggle.
    var fontLigatures: Bool?
    /// Optional font-size override, in points. Uses the same bounds as the editor's
    /// Style pane.
    var fontSize: Double?
    /// Optional canvas-padding override, in points. Uses the same bounds as the editor's
    /// Style pane.
    var padding: Double?
    /// Optional code-card corner radius, in points. Nil preserves the app/preset default.
    var cornerRadius: Double?
    /// Optional drop-shadow blur radius, in points. Nil preserves the app/preset default.
    var shadowRadius: Double?
    /// An explicit terminal reconstruction width (columns), or `nil` to infer it from
    /// the captured output. Only meaningful for `--language terminal`; set by `vgrab -w`
    /// so a known-width capture wraps exactly as it did in the live terminal (CS-070).
    var terminalColumns: Int?
    /// Optional soft-wrap column count for long code lines. Mirrors the editor's
    /// "Wrap long lines" control and stays nil by default so bare renders still
    /// size to content.
    var wrapColumns: Int?
    /// Tidy the loaded source with the same dependency-free formatter as the editor
    /// before rendering. Off by default so a bare CLI render preserves input verbatim.
    var formatCode: Bool = false
    /// The output format. Defaults to PNG; PDF is the supported vector format.
    var format: ExportFormat = .png
    /// The ICC color profile for PNG export (CS-024). PDF ignores this.
    var profile: ColorProfile = .fallback
    /// Render with a real transparent background (no gradient/solid), preserving the
    /// alpha channel on export (CS-024). Overrides any preset background.
    var transparent: Bool = false
    /// Optional built-in gradient or solid-color canvas override. Nil preserves the
    /// app/preset background; the parser keeps it mutually exclusive with transparency.
    var background: BackgroundStyle?
    /// Optional text-only watermark composited by the same overlay as the PRO Brand Kit.
    /// Nil preserves the unwatermarked CLI default.
    var watermarkText: String?
    /// Optional fixed-sRGB tint for `watermarkText`; nil uses the overlay's legible white.
    var watermarkColor: RGBAColor?
    /// Optional corner for `watermarkText`; nil uses the Brand Kit's bottom-right default.
    var watermarkPosition: WatermarkPosition?
    /// Optional frame around `--image` content. Nil preserves the model's plain-image
    /// default; stable CLI ids map onto the app's existing frame enum.
    var imageFrame: ImageFrameOption?
    /// Optional fixed chrome appearance for a framed image. Nil keeps Auto sampling.
    var frameAppearance: ImageFrameAppearance?
    /// Refuse to replace existing image or sidecar files. For batch jobs, existing
    /// outputs are skipped so valid new artifacts can still be produced.
    var noOverwrite: Bool = false

    /// Optional title shown in the rendered window chrome. Separate from the metadata
    /// header, matching the editor's Window Title control.
    var windowTitle: String?
    /// Optional filename chip shown in the metadata header.
    var metadataFilename: String?
    /// Optional filename hint for piped stdin input. It is never read from disk; it
    /// only gives extension-based language inference (and default metadata) the same
    /// filename context a real input file would have.
    var stdinFilename: String?
    /// Optional title shown in the metadata header.
    var metadataTitle: String?
    /// Optional caption shown below the metadata title.
    var metadataCaption: String?
    /// Whether to show the language badge in the metadata header.
    var showLanguageBadge: Bool = false
    /// Optional line-number override. Nil preserves the app/preset default.
    var showLineNumbers: Bool?
    /// Optional window-chrome override. Nil preserves the app/preset default.
    var showChrome: Bool?
    /// Optional drop-shadow override. Nil preserves the app/preset default.
    var showShadow: Bool?
    /// Optional highlighted line ranges, using the same 1-based inclusive model as the
    /// editor's line-highlighting control. Nil preserves the app/preset default.
    var highlightedLineRanges: [ClosedRange<Int>]?
    /// Optional redacted line ranges, using the same 1-based inclusive model as the
    /// editor's secret-redaction control. Nil preserves the app/preset default.
    var redactedLineRanges: [ClosedRange<Int>]?
    /// Automatically scan the rendered visible text for likely secrets and redact the
    /// matching rows before the image or copyable sidecars are written.
    var redactSecrets: Bool = false
    /// Optional focus-mode override. Nil preserves the app/preset default.
    var focusHighlightedLines: Bool?
    /// Optional GitHub-style diff-band override. Nil preserves the app/preset default.
    var diffDecorations: Bool?
    /// For `batch`, walk nested input folders and preserve their relative paths under
    /// the output folder. Off by default so existing batch jobs keep their top-level
    /// behavior unless they opt in.
    var recursiveBatch: Bool = false
    /// For `batch`, return a failing CLI exit if any file was skipped after rendering
    /// the readable files. Useful for CI/docs pipelines that must not silently ignore
    /// invalid input.
    var failOnSkipped: Bool = false
    /// For `batch`, return a failing CLI exit when discovery produces no renderable
    /// files. Useful for CI/docs pipelines with extension filters that must not pass
    /// after doing no work.
    var failOnEmpty: Bool = false
    /// For `batch`, optionally write a JSON report describing skipped input files.
    /// The report is local to the requested path and is written before strict skipped
    /// failures are thrown, so CI can upload it as an artifact.
    var skippedReportPath: String?
    /// For `batch`, optionally write a JSON manifest of rendered outputs (or planned
    /// outputs during `--dry-run`) so CI/docs jobs can publish an exact artifact index.
    var batchManifestPath: String?
    /// For `batch`, scan and load matching files without rendering or writing images.
    /// Useful for CI preflight checks before a docs job spends time producing cards.
    var dryRunBatch: Bool = false
    /// For `batch`, only consider files whose extension is in this normalized lowercase
    /// set. Empty means every regular file is considered before text decoding.
    var batchIncludeExtensions: Set<String> = []
    /// For `batch`, ignore files whose extension is in this normalized lowercase set.
    /// Excluded files are filtered out before loading, so they are not counted as skipped.
    var batchExcludeExtensions: Set<String> = []

    /// Read the source from standard input instead of a file (e.g.
    /// `some-command | vitrine render --stdin`), so the language is inferred from the
    /// content — ANSI-colored terminal output is detected by its escape codes.
    var readStdin: Bool = false
    /// Put the rendered image on the clipboard (instead of, or in addition to,
    /// writing a file). The default for the shell integration's "share now" flow.
    var copyToClipboard: Bool = false
    /// Hand the loaded source to the running app's editor instead of rendering
    /// (`--edit`, behind `vgrab -e`): the CLI stages the text and opens a
    /// `vitrine://edit` URL rather than producing an image. Mutually exclusive with
    /// `--copy`/`--out`, and render-only (not `batch`).
    var openInEditor: Bool = false
    /// Also write a plain-text `.txt` sidecar next to the rendered image, holding the
    /// source as selectable, copyable text (terminal output is stripped of its escape
    /// codes first). Lets a shared image ship with accessible, greppable output. Needs
    /// an `--out` path to sit beside; not meaningful with `--edit`.
    var textSidecar: Bool = false
    /// Also write a Markdown `.md` sidecar next to the rendered image: the image
    /// reference followed by the source in a language-tagged fenced code block, ready
    /// to paste into a README or blog post so viewers can copy the code the image
    /// shows. Same constraints as `textSidecar` (needs `--out`; not with `--edit`).
    var markdownSidecar: Bool = false
    /// Also write a self-contained HTML `.html` sidecar next to the rendered image:
    /// the escaped image embed followed by the escaped source in a language-tagged
    /// `<pre><code>` block, ready to paste into web docs without trusting the source
    /// filename or code as markup. Same constraints as the other sidecars.
    var htmlSidecar: Bool = false

    /// Stable, CLI-facing corner names. Free placement stays an editor-only interaction
    /// because it needs normalized coordinates and visual dragging feedback.
    enum WatermarkPosition: String, CaseIterable, Equatable, Sendable {
        case bottomRight = "bottom-right"
        case bottomLeft = "bottom-left"
        case topRight = "top-right"
        case topLeft = "top-left"

        var displayName: String {
            switch self {
            case .bottomRight: "Bottom right"
            case .bottomLeft: "Bottom left"
            case .topRight: "Top right"
            case .topLeft: "Top left"
            }
        }

        var modelValue: Watermark.Placement {
            switch self {
            case .bottomRight: .bottomTrailing
            case .bottomLeft: .bottomLeading
            case .topRight: .topTrailing
            case .topLeft: .topLeading
            }
        }
    }

    /// Stable automation ids for the image-frame catalog. The model's `macOSWindow`
    /// raw value is intentionally not exposed as CLI syntax.
    enum ImageFrameOption: String, CaseIterable, Equatable, Sendable {
        case none
        case macOSWindow = "macos-window"
        case browser
        case macBook = "macbook"
        case iPhone = "iphone"

        var displayName: String {
            switch self {
            case .none: "None"
            case .macOSWindow: "macOS window"
            case .browser: "Browser"
            case .macBook: "MacBook"
            case .iPhone: "iPhone"
            }
        }

        var modelValue: ImageFrame {
            switch self {
            case .none: .none
            case .macOSWindow: .macOSWindow
            case .browser: .browser
            case .macBook: .macBook
            case .iPhone: .iPhone
            }
        }

        var supportsWindowTitle: Bool { self == .macOSWindow || self == .browser }
    }

    /// Stable automation ids for image-frame chrome appearance.
    enum ImageFrameAppearance: String, CaseIterable, Equatable, Sendable {
        case auto, light, dark

        var displayName: String { rawValue.capitalized }

        var modelValue: FrameAppearance {
            switch self {
            case .auto: .auto
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// The default export scale when neither a preset nor an explicit `--scale`
    /// supplies one — the app's documented default resolution multiplier.
    static let defaultScale = SettingsDefaults.exportScale

    /// Builds the `SnapshotConfig` to render from these options plus the loaded
    /// source `code`, applying the same precedence the GUI uses so the produced
    /// image matches the app.
    ///
    /// Order of application, lowest precedence first:
    ///   1. App defaults (`SnapshotConfig()`).
    ///   2. The destination preset's presentation guidance (padding/background).
    ///   3. The theme override.
    ///   4. The transparent-background override (wins over a preset's background).
    ///   5. CLI presentation overrides.
    ///
    /// `code` and `language` are set from the input file and never altered by a
    /// preset, exactly as in the GUI (a preset is presentation/output only, CS-020).
    func makeConfig(code: String, language: Language) -> SnapshotConfig {
        var config = SnapshotConfig().styled(
            presetID: presetID, themeID: themeID, transparent: transparent)
        if let background { config.background = background }
        config.code = formatCode ? CodeFormatter.tidy(code, language: language) : code
        config.language = language
        if let watermarkText {
            config.watermark = Watermark(
                text: watermarkText,
                logoImageData: nil,
                tint: watermarkColor,
                placement: watermarkPosition?.modelValue ?? .bottomTrailing)
        }
        if let imageFrame { config.imageFrame = imageFrame.modelValue }
        if let frameAppearance { config.imageFrameAppearance = frameAppearance.modelValue }
        config.terminalColumns = terminalColumns
        if let fontName { config.fontName = fontName }
        if let fontLigatures { config.fontLigatures = fontLigatures }
        if let fontSize { config.fontSize = fontSize }
        if let padding { config.padding = padding }
        if let cornerRadius { config.cornerRadius = cornerRadius }
        if let shadowRadius { config.shadowRadius = shadowRadius }
        if let wrapColumns { config.wrapColumns = wrapColumns }
        if let windowTitle { config.windowTitle = windowTitle }
        if let showLineNumbers { config.showLineNumbers = showLineNumbers }
        if let showChrome { config.showChrome = showChrome }
        if let showShadow { config.showShadow = showShadow }
        if let highlightedLineRanges { config.highlightedLineRanges = highlightedLineRanges }
        if let redactedLineRanges { config.redactedLineRanges = redactedLineRanges }
        if redactSecrets {
            let secretRanges = SecretScanner.secretLines(in: config.sidecarText).map { $0...$0 }
            config.redactedLineRanges = LineHighlight.normalize(
                config.redactedLineRanges + secretRanges)
        }
        if let focusHighlightedLines { config.focusHighlightedLines = focusHighlightedLines }
        if let diffDecorations { config.diffDecorations = diffDecorations }
        config.metadata = SnapshotMetadata(
            filename: metadataFilename ?? (readStdin ? stdinFilename : nil),
            title: metadataTitle,
            caption: metadataCaption,
            showLanguageBadge: showLanguageBadge)
        return config
    }

    /// The resolved destination preset, or `nil` when none was requested.
    var resolvedPreset: ExportPreset? { ExportPreset.preset(withID: presetID) }

    /// The effective export scale, applying the GUI's precedence: an explicit
    /// `--scale` wins; otherwise a chosen preset's recommended scale is used; with
    /// neither, the app default. The result is clamped to the valid 1...3 range so a
    /// wild value can never reach the renderer (CS-020/050).
    var effectiveScale: CGFloat {
        let raw = scale ?? resolvedPreset?.scale ?? Self.defaultScale
        return CGFloat(SettingsDefaults.clampExportScale(raw))
    }

    /// The exact logical canvas size to render, when the active preset pins one
    /// (e.g. OpenGraph 1200×630); `nil` lets the canvas hug its content (CS-020).
    var fixedSize: CGSize? { resolvedPreset?.sizing.fixedSize }
}
