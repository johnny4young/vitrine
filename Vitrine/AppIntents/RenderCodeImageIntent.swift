import AppIntents
import Foundation
import OSLog
import UniformTypeIdentifiers

/// A Shortcuts action that renders code text to an image (CS-034).
///
/// This is the headline automation surface: it takes a snippet of code plus optional
/// presentation choices and returns the rendered image as a file the next Shortcut
/// action can save, share, or set as clipboard. It runs the **unchanged** app render
/// path through `SnapshotRenderService`, so its output is identical to what the
/// editor and the `vitrine` CLI produce for the same inputs, and it inherits the
/// app's privacy/sandbox posture — fully local, no network, nothing written to disk
/// by the action itself (the file lives in the Shortcuts-managed transfer location).
///
/// Parameter names are deliberately plain and task-oriented ("Code", "Language",
/// "Theme", "Destination", "Format", "Transparent Background", "Resolution") so the
/// action reads as a sentence in the Shortcuts editor and returns useful output
/// (CS-034 acceptance "clear parameter names and return useful output").
struct RenderCodeImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Render Code to Image"

    static let description = IntentDescription(
        """
        Turns a snippet of code into a polished image using your Vitrine style. \
        The language is detected automatically unless you choose one. Rendering is \
        fully local — nothing leaves your Mac.
        """,
        categoryName: "Rendering"
    )

    /// A render needs AppKit on the main actor and never shows UI, so it runs in the
    /// app process without bringing a window forward.
    static let openAppWhenRun = false
    static let isDiscoverable = true

    @Parameter(
        title: "Code",
        description: "The code text to render.",
        inputOptions: String.IntentInputOptions(
            keyboardType: .default, capitalizationType: .none, multiline: true,
            autocorrect: false, smartQuotes: false, smartDashes: false))
    var code: String

    @Parameter(
        title: "Language",
        description: "The programming language, or Automatic to detect it.",
        default: .automatic)
    var language: SnapshotLanguageAppEnum

    @Parameter(
        title: "Theme",
        description: "The syntax theme, or Default to keep your current one.",
        default: .default)
    var theme: SnapshotThemeAppEnum

    @Parameter(
        title: "Destination",
        description: "A size/style preset for where the image will be posted.",
        // Qualify the enum case: a bare `.none` would bind to `Optional.none` here.
        default: SnapshotPresetAppEnum.none)
    var destination: SnapshotPresetAppEnum

    @Parameter(
        title: "Format",
        description: "Output image format.",
        default: .png)
    var format: SnapshotFormatAppEnum

    @Parameter(
        title: "Transparent Background",
        description: "Render a real transparent background instead of a backdrop.",
        default: false)
    var transparentBackground: Bool

    @Parameter(
        title: "Resolution",
        description: "Export resolution multiplier (1, 2, or 3). Leave empty for the default.",
        inclusiveRange: (1, 3))
    var resolution: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Render \(\.$code) as a \(\.$format) image") {
            \.$language
            \.$theme
            \.$destination
            \.$transparentBackground
            \.$resolution
        }
    }

    /// Renders the code and returns the image as a file result, so the next action in
    /// the Shortcut receives a real image it can save, share, or copy.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let request = SnapshotRenderRequest(
            code: code,
            language: language.language,
            themeID: theme.themeID,
            presetID: destination.presetID,
            scale: resolution,
            format: format.format,
            // The picker forces a deliberate sRGB output for automation; the
            // advanced P3 profile stays an in-app choice (CS-024).
            profile: .sRGB,
            transparent: transparentBackground,
            // Start from the user's live style so the action honors their saved look
            // unless a parameter overrides it.
            baseStyle: AppSettings.shared.config)

        let data: Data
        do {
            data = try SnapshotRenderService.renderData(request)
        } catch let error as SnapshotRenderService.RenderError {
            // Surface a clear, user-facing reason in the Shortcuts error sheet.
            throw IntentRenderError(message: "\(error)")
        }

        let file = IntentFile(
            data: data,
            filename: "vitrine.\(format.format.rawValue)",
            type: format.format == .pdf ? .pdf : .png)
        Log.export.notice(
            "Render Code to Image intent produced a \(format.format.rawValue, privacy: .public)")
        return .result(value: file)
    }
}

/// A small, localized error type for the automation surfaces, so a render failure
/// reads as a sentence in the Shortcuts error sheet rather than a generic failure
/// (CS-034). It is a concrete type thrown directly from `perform()`.
struct IntentRenderError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}
