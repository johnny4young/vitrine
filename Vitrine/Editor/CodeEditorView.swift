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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.setAccessibilityIdentifier("code-editor-text-view")
        textView.setAccessibilityLabel("Code editor")
        scrollView.setAccessibilityIdentifier("code-editor-scroll-view")

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

        init(_ parent: CodeEditorView) { self.parent = parent }

        private var font: NSFont {
            NSFont(name: parent.fontName, size: parent.fontSize)
                ?? .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
        }

        /// True when the style (language/theme/font) differs from what was last applied.
        var styleChanged: Bool {
            appliedLanguage != parent.language
                || appliedThemeID != parent.theme.id
                || appliedFontName != parent.fontName
                || appliedFontSize != parent.fontSize
        }

        /// Applies the monospaced font and 4-space tab stops.
        func configure(_ textView: NSTextView) {
            let font = self.font
            textView.font = font
            let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
            let style = NSMutableParagraphStyle()
            style.tabStops = []
            style.defaultTabInterval = max(spaceWidth * 4, 1)
            textView.defaultParagraphStyle = style
            textView.typingAttributes[.paragraphStyle] = style
            textView.typingAttributes[.font] = font
        }

        /// Recolors the whole document via Highlightr, preserving the selection.
        func applyHighlight(to textView: NSTextView) {
            isHighlighting = true
            defer { isHighlighting = false }

            let selection = textView.selectedRanges
            let attributed = HighlightManager.shared.attributedString(
                for: textView.string, language: parent.language, theme: parent.theme, font: font)
            let mutable = NSMutableAttributedString(attributedString: attributed)
            let paragraph = textView.defaultParagraphStyle ?? NSParagraphStyle.default
            mutable.addAttribute(
                .paragraphStyle, value: paragraph,
                range: NSRange(location: 0, length: mutable.length))
            textView.textStorage?.setAttributedString(mutable)
            textView.selectedRanges = selection

            appliedLanguage = parent.language
            appliedThemeID = parent.theme.id
            appliedFontName = parent.fontName
            appliedFontSize = parent.fontSize
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            debouncer.schedule { [weak textView] in
                guard let textView else { return }
                self.applyHighlight(to: textView)
            }
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
