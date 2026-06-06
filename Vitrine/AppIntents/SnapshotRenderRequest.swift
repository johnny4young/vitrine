import CoreGraphics
import Foundation

/// A pure, value-typed request to render a piece of code text into an image,
/// shared by every automation surface (App Intents and the Services menu, CS-034).
///
/// `SnapshotRenderRequest` is the automation counterpart to the CLI's `CLIOptions`:
/// it carries no AppKit state and does no rendering, so it can be unit-tested off
/// the main actor, and turning it into a `SnapshotConfig` (`makeConfig()`) is what
/// ties automation to the exact same render inputs the editor, quick capture, and
/// the CLI use — the produced image is identical to what the app would make for the
/// same inputs.
///
/// Every optional field defaults to the app's own behavior:
///
/// - `language: nil` infers the language from the text exactly as quick capture does
///   (Markdown fences, file-path hints, then weighted content scoring), so an
///   automation that just hands over a snippet gets the same smart detection.
/// - `themeID: nil` keeps the live style's theme; an explicit id is resolved through
///   the built-in catalog.
/// - `presetID: nil` applies no destination preset; an explicit id reframes the
///   presentation/output (size, scale, background) just like the GUI, and never
///   touches the code (CS-020).
/// - `transparent` forces a real transparent background, winning over a preset's
///   background, mirroring the CLI's `--transparent`.
///
/// The `baseStyle` is the live `SnapshotConfig` an automation should start from
/// (typically `AppSettings.shared.config`), so a Shortcuts action honors the user's
/// saved look unless it overrides a field. It is injected rather than read here so
/// the resolution stays a pure function of its inputs and tests can pin it.
///
/// Main-actor isolated (the module default) so `makeConfig` can apply the
/// main-actor `ExportPreset`/`Theme` model exactly as the GUI does.
struct SnapshotRenderRequest: Equatable {
    /// The code text to render. Required; an automation that hands over empty or
    /// whitespace-only text is rejected before rendering (see `resolvedConfig`).
    var code: String

    /// An explicit language override (e.g. `.swift`), or `nil` to infer it from the
    /// text the same way quick capture does.
    var language: Language?

    /// An explicit syntax-theme id (e.g. `"dracula"`), or `nil` to keep the live
    /// style's theme. An unknown id resolves to One Dark via the catalog lookup.
    var themeID: String?

    /// An explicit destination-preset id (e.g. `"opengraph"`), or `nil` for no
    /// preset. A preset reframes presentation/output only and never the source.
    var presetID: String?

    /// The export resolution multiplier (1/2/3), or `nil` to use the preset's
    /// recommended scale, falling back to the app default. Clamped to 1...3.
    var scale: Int?

    /// The output image format. PNG is the default; PDF is the vector option.
    var format: ExportFormat = .png

    /// The ICC color profile for PNG export (CS-024). PDF ignores this.
    var profile: ColorProfile = .sRGB

    /// Render a real transparent background, preserving alpha on export and winning
    /// over any preset background (CS-024). Off by default.
    var transparent: Bool = false

    /// The live style an automation starts from before applying its overrides —
    /// usually `AppSettings.shared.config`. Defaults to the factory configuration so
    /// a request can be built and tested without the shared settings singleton.
    var baseStyle = SnapshotConfig()

    /// Builds the `SnapshotConfig` to render, applying the same precedence the GUI
    /// and CLI use so the produced image matches the app.
    ///
    /// Order of application, lowest precedence first:
    ///   1. The live `baseStyle` (the user's saved look).
    ///   2. The destination preset's presentation guidance (padding/background).
    ///   3. The theme override.
    ///   4. The transparent-background override (wins over a preset's background).
    ///
    /// The code is set from `code` and the language from `resolvedLanguage`; neither
    /// is ever altered by a preset (a preset is presentation/output only, CS-020).
    func makeConfig() -> SnapshotConfig {
        var config = baseStyle
        config.code = code
        config.language = resolvedLanguage

        if let preset = resolvedPreset {
            preset.apply(to: &config)
        }
        if let themeID {
            // Resolve through the custom-theme store so a Shortcuts/Services theme id can
            // name a user custom theme (CS-031); it falls back to built-ins, matching the GUI.
            config.theme = CustomThemeStore.shared.theme(withID: themeID)
        }
        // Transparency is the last word on the background so it layers cleanly onto
        // any preset (the automation asked for real alpha regardless).
        if transparent {
            config.background = .transparent
        }
        return config
    }

    /// The language to render with: an explicit override when given, otherwise the
    /// language inferred from the text using the same interpreter quick capture
    /// uses, so automation gets the app's smart detection (Markdown fences,
    /// file-path hints, then content scoring).
    var resolvedLanguage: Language {
        language ?? LanguageDetector.interpret(code).language
    }

    /// The resolved destination preset, or `nil` when none was requested.
    var resolvedPreset: ExportPreset? { ExportPreset.preset(withID: presetID) }

    /// The effective export scale, applying the GUI's precedence: an explicit scale
    /// wins; otherwise a chosen preset's recommended scale is used; with neither, the
    /// app default. Clamped to the valid 1...3 range so a wild value can never reach
    /// the renderer (CS-020/050).
    var effectiveScale: CGFloat {
        let raw = scale ?? resolvedPreset?.scale ?? SettingsDefaults.exportScale
        return CGFloat(SettingsDefaults.clampExportScale(raw))
    }

    /// The exact logical canvas size to render, when the active preset pins one
    /// (e.g. OpenGraph 1200×630); `nil` lets the canvas hug its content (CS-020).
    var fixedSize: CGSize? { resolvedPreset?.sizing.fixedSize }

    /// Whether the request carries usable (non-empty) code. An automation that hands
    /// over empty or whitespace-only text has nothing to render and is rejected up
    /// front with a clear error rather than producing a blank image.
    var hasRenderableCode: Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
