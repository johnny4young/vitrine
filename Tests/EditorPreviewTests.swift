import Testing

@testable import Vitrine

/// Covers the editor's hero-preview helper (CS-037): the empty-state sample is
/// shown in the preview without ever mutating the user's document.
@Suite("Editor preview (CS-037)")
struct EditorPreviewTests {
    @Test func emptyDocumentPreviewsTheSampleWithoutMutatingTheDocument() {
        var live = SnapshotConfig()
        live.code = ""

        let preview = EditorPreview.configForPreview(live)

        // The preview shows the sample so the stage is never a blank card…
        #expect(preview.code == EditorPreview.sampleCode)
        #expect(!preview.code.isEmpty)
        // …but the live document the caller still holds is untouched.
        #expect(live.code.isEmpty)
    }

    @Test func whitespaceOnlyDocumentCountsAsEmpty() {
        var live = SnapshotConfig()
        live.code = "   \n\t  \n"

        #expect(EditorPreview.isEffectivelyEmpty(live.code))
        #expect(EditorPreview.configForPreview(live).code == EditorPreview.sampleCode)
    }

    @Test func realCodeIsPreviewedVerbatim() {
        var live = SnapshotConfig()
        live.code = "let answer = 42"

        let preview = EditorPreview.configForPreview(live)

        #expect(!EditorPreview.isEffectivelyEmpty(live.code))
        // Real content is returned unchanged — the sample never overrides it.
        #expect(preview.code == "let answer = 42")
        #expect(preview == live)
    }

    @Test func previewKeepsTheUsersStyleAndPresets() {
        // Substituting the sample must keep the user's chosen look so the empty
        // state shows what *their* settings produce, not a generic default.
        var live = SnapshotConfig()
        live.code = ""
        live.theme = Theme.dracula
        live.padding = 56
        live.background = .solid(RGBAColor(.white))

        let preview = EditorPreview.configForPreview(live)

        #expect(preview.theme.id == Theme.dracula.id)
        #expect(preview.padding == 56)
        #expect(preview.background == .solid(RGBAColor(.white)))
        // Only the code was swapped.
        #expect(preview.code == EditorPreview.sampleCode)
    }
}
