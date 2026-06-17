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

    /// The source file to read the code from (a folder for `batch`). The language is
    /// inferred from its extension (falling back to content detection), matching the
    /// editor's drag-and-drop loader (CS-027/028).
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
    /// The output format. Defaults to PNG; PDF is the supported vector format.
    var format: ExportFormat = .png
    /// The ICC color profile for PNG export (CS-024). PDF ignores this.
    var profile: ColorProfile = .fallback
    /// Render with a real transparent background (no gradient/solid), preserving the
    /// alpha channel on export (CS-024). Overrides any preset background.
    var transparent: Bool = false

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
    ///
    /// `code` and `language` are set from the input file and never altered by a
    /// preset, exactly as in the GUI (a preset is presentation/output only, CS-020).
    func makeConfig(code: String, language: Language) -> SnapshotConfig {
        var config = SnapshotConfig().styled(
            presetID: presetID, themeID: themeID, transparent: transparent)
        config.code = code
        config.language = language
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
