import Testing

@testable import Vitrine

@Suite("Code formatter — JSON")
struct CodeFormatterJSONTests {
    // MARK: - formatJSON

    /// A minified object is re-indented two spaces, preserving key order (which
    /// `JSONSerialization` would not).
    @Test func formatJSONReindentsAndPreservesKeyOrder() {
        let input = #"{"zebra":1,"apple":2,"nested":{"b":true,"a":null}}"#
        let expected = """
            {
              "zebra": 1,
              "apple": 2,
              "nested": {
                "b": true,
                "a": null
              }
            }
            """
        #expect(CodeFormatter.formatJSON(input) == expected)
    }

    /// Empty containers collapse onto a single line.
    @Test func formatJSONCollapsesEmptyContainers() {
        #expect(CodeFormatter.formatJSON(#"{"a":{},"b":[]}"#) == "{\n  \"a\": {},\n  \"b\": []\n}")
    }

    /// Braces, brackets, and commas inside string literals are left untouched.
    @Test func formatJSONIsStringAndEscapeAware() {
        let input = #"{"text":"a, {b} [c] \"quoted\""}"#
        let expected = "{\n  \"text\": \"a, {b} [c] \\\"quoted\\\"\"\n}"
        #expect(CodeFormatter.formatJSON(input) == expected)
    }

    /// An array of objects re-indents structurally.
    @Test func formatJSONHandlesArraysOfObjects() {
        let expected = """
            [
              {
                "id": 1
              },
              {
                "id": 2
              }
            ]
            """
        #expect(CodeFormatter.formatJSON(#"[{"id":1},{"id":2}]"#) == expected)
    }

    /// Non-JSON input (and truncated JSON) returns `nil` so it is never reshaped.
    @Test func formatJSONRejectsNonJSON() {
        #expect(CodeFormatter.formatJSON("let x = 1") == nil)
        #expect(CodeFormatter.formatJSON(#"{"a": 1"#) == nil)  // unterminated
        #expect(CodeFormatter.formatJSON("42") == nil)  // bare fragment, not an object/array
    }
}
