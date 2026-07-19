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

// MARK: - Debounced preview code

extension EditorPreviewTests {
    /// Before the first debounce sync (`stagedCode == nil`), the preview uses the live
    /// document code, so the stage is correct from the first frame — no flash of the
    /// empty-state sample when a window opens onto real code.
    @Test func nilStagedCodeUsesTheLiveCode() {
        var live = SnapshotConfig()
        live.code = "let live = 1"
        let preview = EditorPreview.configForPreview(live, stagedCode: nil)
        #expect(preview.code == "let live = 1")
    }

    /// Once staged, the preview renders the debounced code, not the live keystroke —
    /// this is the whole point: the cache key stays stable between keystrokes.
    @Test func stagedCodeIsWhatThePreviewRenders() {
        var live = SnapshotConfig()
        live.code = "let live = 999"  // the just-typed character the preview should NOT chase
        let preview = EditorPreview.configForPreview(live, stagedCode: "let staged = 1")
        #expect(preview.code == "let staged = 1")
    }

    /// Only `code` is debounced: a style edit reaches the preview immediately even
    /// though the code is still the older staged copy.
    @Test func styleEditsBypassTheCodeDebounce() {
        var live = SnapshotConfig()
        live.code = "let live = 1"
        live.theme = Theme.dracula
        live.padding = 64
        let preview = EditorPreview.configForPreview(live, stagedCode: "let staged = 1")
        #expect(preview.code == "let staged = 1", "code trails behind…")
        #expect(preview.theme.id == Theme.dracula.id, "…but style is immediate")
        #expect(preview.padding == 64)
    }

    /// A staged code that is empty still falls back to the sample, so deleting all the
    /// text leaves the stage showing the placeholder rather than a blank card.
    @Test func emptyStagedCodeStillFallsBackToTheSample() {
        var live = SnapshotConfig()
        live.code = "  "
        let preview = EditorPreview.configForPreview(live, stagedCode: "")
        #expect(preview.code == EditorPreview.sampleCode)
    }

    @Test func theDebounceWindowIsShortButNonZero() {
        #expect(EditorPreview.previewCodeDebounce > .zero)
        #expect(EditorPreview.previewCodeDebounce <= .milliseconds(150))
    }
}
