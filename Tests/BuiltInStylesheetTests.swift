import AppKit
import Testing
import VitrineDomain

@testable import VitrineRendering

@Suite("Built-in stylesheet")
struct BuiltInStylesheetTests {
    private let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private func hex(_ color: Any?) -> String? {
        guard let rgb = (color as? NSColor)?.usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02x%02x%02x", Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)), Int(round(rgb.blueComponent * 255)))
    }

    private func color(of text: String, in string: NSAttributedString) -> String? {
        let range = (string.string as NSString).range(of: text)
        guard range.location != NSNotFound else { return nil }
        return hex(string.attribute(.foregroundColor, at: range.location, effectiveRange: nil))
    }

    @Test func laterRuleWinsForAClassTwoRulesStyle() {
        let sheet = BuiltInStylesheet(
            css: ".hljs{color:#000000}.hljs-meta{color:#111111}.hljs-meta{color:#222222}")
        let result = sheet.attributedString(
            html: "<span class=\"hljs-meta\">@main</span>", font: font)
        #expect(color(of: "@main", in: result) == "#222222")
    }

    @Test func descendantSelectorStylesOnlyInsideItsAncestor() {
        let sheet = BuiltInStylesheet(
            css: ".hljs-meta .hljs-string{color:#00ff00}.hljs-meta{color:#0000ff}"
                + ".hljs-string{color:#ff0000}")
        let html =
            "<span class=\"hljs-meta\">@attr(<span class=\"hljs-string\">\"in\"</span>)</span>"
            + " <span class=\"hljs-string\">\"out\"</span>"
        let result = sheet.attributedString(html: html, font: font)
        #expect(color(of: "@attr", in: result) == "#0000ff")
        #expect(color(of: "\"in\"", in: result) == "#00ff00")
        #expect(color(of: "\"out\"", in: result) == "#ff0000")
    }

    @Test func compoundAndPseudoSelectorsDoNotMatch() {
        let sheet = BuiltInStylesheet(
            css: ".hljs{color:#000000}.hljs-title.function_{color:#ff0000}"
                + ".hljs ::selection{color:#00ff00}")
        let result = sheet.attributedString(
            html: "<span class=\"hljs-title function_\">run</span> x", font: font)
        #expect(color(of: "run", in: result) == "#000000")
        #expect(color(of: "x", in: result) == "#000000")
    }

    @Test func elementQualifiedHljsRuleSetsTheBackground() {
        let sheet = BuiltInStylesheet(css: "pre code.hljs{display:block}.hljs{background:#123456}")
        #expect(hex(sheet.background) == "#123456")
    }

    @Test func boldTokensUseTheBaseFamilyBoldVariant() {
        let sheet = BuiltInStylesheet(css: ".hljs-keyword{font-weight:bold}")
        let result = sheet.attributedString(
            html: "<span class=\"hljs-keyword\">let</span>", font: font)
        let runFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(runFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(runFont?.pointSize == font.pointSize)
    }

    @Test func decodesEscapedText() {
        let sheet = BuiltInStylesheet(css: "")
        let result = sheet.attributedString(html: "a &lt;T&gt; &amp;&amp; &#x27;b&#39;", font: font)
        #expect(result.string == "a <T> && 'b'")
    }

    /// One Dark styles `.hljs-meta` and, through `.hljs-meta .hljs-string`, strings inside it;
    /// a Swift attribute must always take the `.hljs-meta` color.
    @Test func oneDarkSwiftAttributeKeepsTheMetaColor() {
        let result = HighlightManager.shared.attributedString(
            for: "@ViewBuilder\nvar body: some View { Text(\"hi\") }", language: .swift,
            theme: .oneDark, font: font)
        #expect(color(of: "@ViewBuilder", in: result) == "#61aeee")
        #expect(color(of: "\"hi\"", in: result) == "#98c379")
    }
}
