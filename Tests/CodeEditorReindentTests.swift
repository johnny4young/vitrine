import AppKit
import SwiftUI
import Testing

@testable import Vitrine

// — the paste → re-indent pipeline inside the editor's NSTextView.
//
// `CodeFormatter.tidy` is covered as pure logic in CodeFormatterTests; what this
// suite pins is the *editor wiring*: the coordinator applies the tidied text
// through the text view's native edit cycle, so the reformat is a single undoable
// edit (⌘Z restores the exact pasted text), and a no-op paste registers nothing.

@MainActor
@Suite("Paste re-indent goes through the editor's undo cycle")
struct CodeEditorReindentTests {
    /// A coordinator bound to a throwaway editor view; the binding is constant
    /// because these tests assert on the text view, not the SwiftUI write-back.
    private func makeCoordinator(
        language: Language = .javascript
    )
        -> CodeEditorView.Coordinator
    {
        CodeEditorView.Coordinator(
            CodeEditorView(
                text: .constant(""),
                language: language,
                theme: .oneDark,
                fontName: "SF Mono",
                fontSize: 13,
                fontLigatures: false))
    }

    /// A text view hosted in a window so the responder chain supplies an undo
    /// manager, exactly like the live editor (a window creates one when its
    /// delegate supplies none).
    private func makeHostedTextView(_ string: String) -> (NSWindow, NSTextView) {
        let textView = NSTextView()
        textView.allowsUndo = true
        textView.string = string
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        // ARC owns the window in this test; the AppKit default (release on close)
        // would over-release it and crash the test host.
        window.isReleasedWhenClosed = false
        window.contentView = textView
        return (window, textView)
    }

    private static let messyJSX =
        "<Button\n        variant=\"contained\"\n        onClick={() => save()}\n    >\n        Cancel\n    </Button>"

    @Test func enabledPasteReindentsAndOneUndoRestoresThePastedText() throws {
        let coordinator = makeCoordinator()
        let (window, textView) = makeHostedTextView(Self.messyJSX)
        defer { window.close() }

        coordinator.reindentAfterPaste(textView, isEnabled: true)

        let expected = CodeFormatter.tidy(Self.messyJSX, language: .javascript)
        #expect(textView.string == expected)
        #expect(textView.string != Self.messyJSX, "Fixture must actually need re-indenting")

        // The reformat is one undoable edit: a single undo restores the paste.
        let undoManager = try #require(textView.undoManager)
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(textView.string == Self.messyJSX)
    }

    @Test func disabledPreferenceLeavesThePastedTextUntouched() {
        let coordinator = makeCoordinator()
        let (window, textView) = makeHostedTextView(Self.messyJSX)
        defer { window.close() }

        coordinator.reindentAfterPaste(textView, isEnabled: false)

        #expect(textView.string == Self.messyJSX)
        #expect(textView.undoManager?.canUndo == false)
    }

    @Test func alreadyTidyPasteRegistersNoUndoableEdit() {
        let tidy = CodeFormatter.tidy(Self.messyJSX, language: .javascript)
        let coordinator = makeCoordinator()
        let (window, textView) = makeHostedTextView(tidy)
        defer { window.close() }

        coordinator.reindentAfterPaste(textView, isEnabled: true)

        #expect(textView.string == tidy)
        #expect(
            textView.undoManager?.canUndo == false,
            "A no-op reformat must not push an undo entry")
    }

    @Test func leaveAloneLanguageNeverRewritesThePaste() {
        // Diff hunks carry meaningful leading characters; the formatter routes them
        // to `.leaveAlone`, so a paste in a diff document must never be rewritten.
        let diff = "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-    old\n+        new"
        let coordinator = makeCoordinator(language: .diff)
        let (window, textView) = makeHostedTextView(diff)
        defer { window.close() }

        coordinator.reindentAfterPaste(textView, isEnabled: true)

        #expect(textView.string == diff)
        #expect(textView.undoManager?.canUndo == false)
    }
}
