import AppIntents
import OSLog

/// A Shortcuts action that opens a snippet of code in the Vitrine editor (CS-034).
///
/// Where `RenderCodeImageIntent` produces a file headlessly, this action is the
/// "hand it to me to finish" path: it loads the code (and an optional language) into
/// the editor and brings the window forward, so a user can tweak the style before
/// exporting. It is the automation analogue of quick capture deferring a complex
/// paste to the editor.
///
/// It opens the app because its whole purpose is to surface a window; it still does
/// no network and writes nothing to disk, so the privacy/sandbox posture is intact.
struct OpenCodeInEditorIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Code in Editor"

    static let description = IntentDescription(
        """
        Loads code into the Vitrine editor so you can choose a style and export it. \
        Rendering stays fully local.
        """,
        categoryName: "Editing"
    )

    /// This action exists to show the editor, so it brings the app forward.
    static let openAppWhenRun = true

    @Parameter(
        title: "Code",
        description: "The code text to load into the editor.",
        inputOptions: String.IntentInputOptions(
            keyboardType: .default, capitalizationType: .none, multiline: true,
            autocorrect: false, smartQuotes: false, smartDashes: false))
    var code: String

    @Parameter(
        title: "Language",
        description: "The programming language, or Automatic to detect it.",
        default: .automatic)
    var language: SnapshotLanguageAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$code) in the Vitrine editor") {
            \.$language
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Resolve the language the same way quick capture does when none is given,
        // so a snippet loads with correct highlighting out of the box.
        let resolved = language.language ?? LanguageDetector.interpret(code).language

        let settings = AppSettings.shared
        settings.config.code = code
        settings.config.language = resolved
        settings.noteLanguageUsed(resolved)

        EditorWindowController.shared.show()
        Log.app.notice("Open Code in Editor intent loaded a snippet into the editor")
        return .result()
    }
}
