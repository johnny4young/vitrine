import AppKit
import SwiftUI
import Testing

@testable import Vitrine

// P4 — the editor's syntax re-highlight applies attributes in place.
//
// Highlighting only recolors; it never changes the characters. These pin that the
// coordinator's `applyHighlight` recolors the document without disturbing the text or
// the selection, and that re-applying it is idempotent — the guarantees the in-place
// attribute pass (instead of a full `setAttributedString`) must preserve.

@MainActor
@Suite("Editor re-highlight applies attributes in place · P4")
struct CodeEditorHighlightTests {
    private func makeCoordinator(language: Language = .swift) -> CodeEditorView.Coordinator {
        CodeEditorView.Coordinator(
            CodeEditorView(
                text: .constant(""),
                language: language,
                theme: .oneDark,
                fontName: "SF Mono",
                fontSize: 13,
                fontLigatures: false))
    }

    private func makeHostedTextView(_ string: String) -> (NSWindow, NSTextView) {
        let textView = NSTextView()
        textView.allowsUndo = true
        textView.string = string
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        return (window, textView)
    }

    @Test func recolorsWithoutChangingCharactersOrSelection() throws {
        let coordinator = makeCoordinator(language: .swift)
        let code = "func greet() {\n    let x = 42\n    return x\n}"
        let (window, textView) = makeHostedTextView(code)
        defer { window.close() }
        coordinator.configure(textView)

        let selection = NSRange(location: 5, length: 5)
        textView.setSelectedRange(selection)

        coordinator.applyHighlight(to: textView)

        // The characters are untouched — only their attributes change…
        #expect(textView.string == code)
        // …and the selection (character-index based) survives the in-place recolor.
        #expect(textView.selectedRange() == selection)

        // Syntax coloring actually landed: more than one foreground color across the doc.
        let storage = try #require(textView.textStorage)
        var colors = Set<NSColor>()
        storage.enumerateAttribute(
            .foregroundColor, in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color) }
        }
        #expect(colors.count >= 2, "syntax highlighting should paint multiple colors")

        // The paragraph style (tab stops) is applied over the whole document.
        let paragraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        #expect(paragraph is NSParagraphStyle)
    }

    @Test func reapplyingIsIdempotent() throws {
        let coordinator = makeCoordinator(language: .swift)
        let code = "let answer = 42\nprint(answer)"
        let (window, textView) = makeHostedTextView(code)
        defer { window.close() }
        coordinator.configure(textView)

        coordinator.applyHighlight(to: textView)
        let first = try #require(textView.textStorage?.copy() as? NSAttributedString)
        coordinator.applyHighlight(to: textView)
        let second = try #require(textView.textStorage?.copy() as? NSAttributedString)

        #expect(first.isEqual(to: second), "re-highlighting the same text is stable")
        #expect(textView.string == code)
    }
}
