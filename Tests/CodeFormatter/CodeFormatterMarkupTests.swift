import Testing

@testable import Vitrine

@Suite("Code formatter — markup")
struct CodeFormatterMarkupTests {
    // MARK: - formatMarkup

    /// Compact HTML expands into a readable element hierarchy while leaf text stays
    /// inline, avoiding whitespace changes inside user-visible copy.
    @Test func formatMarkupExpandsNestedHTMLAndKeepsLeafTextInline() {
        let input =
            #"<!doctype html><main class="card"><h1>Vitrine</h1><p>Ship polished code.</p><img src="preview.png"></main>"#
        let expected = """
            <!doctype html>
            <main class="card">
              <h1>Vitrine</h1>
              <p>Ship polished code.</p>
              <img src="preview.png">
            </main>
            """
        #expect(CodeFormatter.formatMarkup(input) == expected)
    }

    /// XML declarations, namespaces, quoted `>` characters, comments, and self-closing
    /// elements are tokenized without normalizing their original bytes.
    @Test func formatMarkupHandlesXMLSyntaxAndQuotedTagDelimiters() {
        let input =
            #"<?xml version="1.0"?><feed xmlns:x="urn:test"><!--keep--><x:item value="a > b"/></feed>"#
        let expected = """
            <?xml version="1.0"?>
            <feed xmlns:x="urn:test">
              <!--keep-->
              <x:item value="a > b"/>
            </feed>
            """
        #expect(CodeFormatter.formatMarkup(input) == expected)
    }

    /// CDATA carries text semantics, so it stays inline with its leaf instead of gaining
    /// formatting whitespace around the section.
    @Test func formatMarkupPreservesInlineCDATAAsText() {
        #expect(
            CodeFormatter.formatMarkup("<root><![CDATA[a < b]]></root>")
                == "<root><![CDATA[a < b]]></root>")
    }

    /// Reformatting the result is a no-op, so repeated Format Code commands never drift.
    @Test func formatMarkupIsIdempotent() throws {
        let formatted = try #require(CodeFormatter.formatMarkup("<a><b>value</b></a>"))
        #expect(CodeFormatter.formatMarkup(formatted) == formatted)
    }

    /// Mixed content and raw-text containers are whitespace-sensitive; malformed trees
    /// are unsafe. All return nil so the caller can take its non-destructive fallback.
    @Test func formatMarkupRejectsSemanticallyUnsafeOrMalformedInput() {
        #expect(CodeFormatter.formatMarkup("<p>Hello <em>world</em>!</p>") == nil)
        #expect(CodeFormatter.formatMarkup("<pre>  keep\n spacing</pre>") == nil)
        #expect(CodeFormatter.formatMarkup("<div><span></div>") == nil)
        #expect(CodeFormatter.formatMarkup("not markup") == nil)
    }
}
