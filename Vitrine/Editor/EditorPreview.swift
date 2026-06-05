import Foundation

/// Pure helpers backing the editor's hero preview (CS-037).
///
/// The redesign gives the live preview center stage, and when the document is
/// empty it shows a representative **sample** so the canvas is never a blank card
/// (CS-037 "empty editor state shows a sample"). That sample must be shown *only*
/// in the preview — it can never leak into the user's document, or opening the
/// editor and exporting nothing would silently capture code the user never wrote.
///
/// This logic lives in a value type, free of SwiftUI/AppKit, so the invariant is
/// unit-testable without driving the view: ``configForPreview(_:)`` derives the
/// config the stage renders, and the caller's own `settings.config` is never
/// mutated.
enum EditorPreview {
    /// A short Swift sample used only for the empty-state preview. Intentionally
    /// tiny and self-evidently a placeholder, so a sighted user reads it as "this
    /// is what an image looks like" rather than real content.
    static let sampleCode = """
        func greet(_ name: String) -> String {
            "Hello, \\(name)!"
        }
        """

    /// Whether `code` is effectively empty (only whitespace), in which case the
    /// preview should fall back to the sample.
    static func isEffectivelyEmpty(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The config the center stage should render for `config`.
    ///
    /// When the document carries real code, the live config is returned unchanged.
    /// When it is empty, a *copy* with the sample code substituted is returned —
    /// the input is taken by value, so the caller's live config is never touched.
    /// Only `code` is swapped; the user's chosen style/presets still drive the
    /// preview, so the sample shows what *their* settings produce.
    static func configForPreview(_ config: SnapshotConfig) -> SnapshotConfig {
        guard isEffectivelyEmpty(config.code) else { return config }
        var sample = config
        sample.code = sampleCode
        return sample
    }
}
