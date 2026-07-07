import AppKit
import SwiftUI

/// Code text editor backed by `NSTextView` with live syntax highlighting (CS-003):
/// debounced recolor (~100 ms), monospaced font, Tab = 4 spaces, no autocorrect.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var language: Language
    var theme: Theme
    var fontName: String
    var fontSize: Double
    var fontLigatures: Bool
    /// Called when a paste replaced the *entire* document (a select-all paste or a
    /// paste into an empty editor) — i.e. a new capture — so the editor can clear
    /// content-bound marks that no longer apply. A mid-edit insert does not fire it.
    var onReplaceAllPaste: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        // A `CodeTextView` (an `NSTextView` subclass) so a native ⌘V paste can be
        // intercepted for auto re-indent (CS-049); the rest mirrors the standard
        // `NSTextView.scrollableTextView()` setup.
        let textView = CodeTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        // Transparent over the code panel's glass (design/handoff): the panel
        // material shows through behind the highlighted text.
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 12)
        textView.string = text
        textView.setAccessibilityIdentifier("code-editor-text-view")
        textView.setAccessibilityLabel("Code editor")
        scrollView.setAccessibilityIdentifier("code-editor-scroll-view")

        // After a native ⌘V paste, re-indent through the coordinator (CS-049); the
        // coordinator checks the user's preference and uses the undo-aware edit cycle.
        textView.onPaste = { [weak textView] replacedEntireDocument in
            guard let textView else { return }
            context.coordinator.reindentAfterPaste(textView)
            // A select-all paste (or a paste into an empty editor) is a new capture, so
            // drop content-bound marks that were positioned over the old code.
            if replacedEntireDocument { context.coordinator.parent.onReplaceAllPaste() }
        }

        context.coordinator.configure(textView)
        context.coordinator.applyHighlight(to: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.configure(textView)

        if textView.string != text {
            // External change (e.g. reopening a recent capture): sync + recolor now.
            textView.string = text
            coordinator.applyHighlight(to: textView)
        } else if coordinator.styleChanged {
            // Theme/language/font changed: recolor now (text edits are debounced).
            coordinator.applyHighlight(to: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        private let debouncer = Debouncer(interval: .milliseconds(100))
        private var isHighlighting = false

        private var appliedLanguage: Language?
        private var appliedThemeID: String?
        private var appliedFontName: String?
        private var appliedFontSize: Double?
        private var appliedFontLigatures: Bool?

        init(_ parent: CodeEditorView) { self.parent = parent }

        private var font: NSFont {
            CodeFont.resolved(
                family: parent.fontName, size: parent.fontSize, ligatures: parent.fontLigatures)
        }

        /// True when the style (language/theme/font, including ligatures) differs
        /// from what was last applied.
        var styleChanged: Bool {
            appliedLanguage != parent.language
                || appliedThemeID != parent.theme.id
                || appliedFontName != parent.fontName
                || appliedFontSize != parent.fontSize
                || appliedFontLigatures != parent.fontLigatures
        }

        /// Applies the monospaced font and 4-space tab stops.
        func configure(_ textView: NSTextView) {
            let font = self.font
            textView.font = font
            let spaceWidth = CodeFont.advance(of: " ", in: font)
            let style = NSMutableParagraphStyle()
            style.tabStops = []
            style.defaultTabInterval = max(spaceWidth * 4, 1)
            textView.defaultParagraphStyle = style
            textView.typingAttributes[.paragraphStyle] = style
            textView.typingAttributes[.font] = font
        }

        /// Recolors the whole document via Highlightr, preserving the selection.
        ///
        /// Highlighting never changes the *characters* — only their colors — so when the
        /// rendered text matches the storage's text (the normal case), the new attributes
        /// are applied **in place** over the existing characters rather than replacing the
        /// whole string. A full `setAttributedString` re-seats every character and forces
        /// the layout manager to regenerate all glyphs, which is what spiked on a 1–2k-line
        /// document; an attribute-only pass (`beginEditing`/`endEditing`) reuses the glyphs
        /// and only re-processes the changed attributes (P4). The rare case where the
        /// rendered text differs (e.g. a custom theme trims a trailing newline) falls back
        /// to the selection-preserving full replace.
        func applyHighlight(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            isHighlighting = true
            defer { isHighlighting = false }

            let attributed = HighlightManager.shared.attributedString(
                for: textView.string, language: parent.language, theme: parent.theme, font: font)
            let paragraph = textView.defaultParagraphStyle ?? NSParagraphStyle.default

            if attributed.string == storage.string {
                // Same characters: recolor in place. Selection is character-index based, so
                // it survives untouched; no save/restore needed.
                let full = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                attributed.enumerateAttributes(
                    in: NSRange(location: 0, length: attributed.length)
                ) { attributes, range, _ in
                    storage.setAttributes(attributes, range: range)
                }
                storage.addAttribute(.paragraphStyle, value: paragraph, range: full)
                storage.endEditing()
            } else {
                // Characters differ from the render: fall back to a full, selection-
                // preserving replace.
                let selection = textView.selectedRanges
                let mutable = NSMutableAttributedString(attributedString: attributed)
                mutable.addAttribute(
                    .paragraphStyle, value: paragraph,
                    range: NSRange(location: 0, length: mutable.length))
                storage.setAttributedString(mutable)
                textView.selectedRanges = selection
            }

            appliedLanguage = parent.language
            appliedThemeID = parent.theme.id
            appliedFontName = parent.fontName
            appliedFontSize = parent.fontSize
            appliedFontLigatures = parent.fontLigatures
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            debouncer.schedule { [weak textView] in
                guard let textView else { return }
                self.applyHighlight(to: textView)
            }
        }

        /// Re-indents the whole document after a paste, when the user's preference is on,
        /// through the text view's native edit cycle so the change lands on the undo stack
        /// (⌘Z reverts it) and `textDidChange` writes it back to the binding (CS-049). A
        /// no-op (already tidy, or a `.leaveAlone` language) registers no edit.
        ///
        /// `isEnabled` defaults to the live global preference; tests pass it explicitly
        /// so the behavior is assertable without touching shared defaults.
        func reindentAfterPaste(
            _ textView: NSTextView, isEnabled: Bool = AppSettings.shared.reindentOnPaste
        ) {
            guard isEnabled else { return }
            let original = textView.string
            let tidied = CodeFormatter.tidy(original, language: parent.language)
            guard tidied != original else { return }
            let whole = NSRange(location: 0, length: (original as NSString).length)
            guard textView.shouldChangeText(in: whole, replacementString: tidied) else { return }
            textView.textStorage?.replaceCharacters(in: whole, with: tidied)
            textView.didChangeText()  // fires the delegate → writes back to the binding
            textView.undoManager?.setActionName(String(localized: "Format Code"))
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.insertText("    ", replacementRange: textView.selectedRange())
                return true
            }
            return false
        }
    }
}

/// `NSTextView` subclass that notifies after a paste so the editor can re-indent the
/// result (CS-049). Paste is the one mutation with no `NSTextViewDelegate` hook, so it
/// is overridden here; every other edit flows through the coordinator's delegate
/// callbacks. `super.paste` honors `isRichText = false`, so it inserts plain text.
final class CodeTextView: NSTextView {
    /// Invoked right after a paste lands so the coordinator can tidy the indentation
    /// when the user's preference is on. The flag reports whether the paste replaced
    /// the *entire* document (a select-all paste, or a paste into an empty editor),
    /// which the editor treats as a new capture.
    var onPaste: ((_ replacedEntireDocument: Bool) -> Void)?

    override func paste(_ sender: Any?) {
        // Measure the replacement target *before* the paste mutates the text.
        let lengthBefore = (string as NSString).length
        let selection = selectedRange()
        let replacedEntireDocument =
            lengthBefore == 0 || (selection.location == 0 && selection.length == lengthBefore)
        super.paste(sender)
        onPaste?(replacedEntireDocument)
    }
}
