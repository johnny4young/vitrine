import Testing

@testable import Vitrine

/// CS-049 — language-aware code tidying (structural re-indent + dedent + JSON re-indent,
/// routed per language family).
@Suite("Code formatter")
struct CodeFormatterTests {

    // MARK: - dedent

    /// A block copied from deep inside a file loses its uniform left margin but keeps
    /// its relative indentation.
    @Test func dedentStripsTheCommonLeadingMargin() {
        let input = "        let a = 1\n            let b = 2\n        return a + b"
        let expected = "let a = 1\n    let b = 2\nreturn a + b"
        #expect(CodeFormatter.dedent(input) == expected)
    }

    /// Blank and whitespace-only lines do not count toward the common prefix and are
    /// emitted empty (no surviving trailing indentation).
    @Test func dedentIgnoresBlankLinesForTheCommonPrefix() {
        let input = "    a\n\n      \n    b"
        #expect(CodeFormatter.dedent(input) == "a\n\n\nb")
    }

    /// When the lines share no common leading whitespace, the input is returned as-is.
    @Test func dedentLeavesFlushLeftCodeUnchanged() {
        let input = "func main() {\n    body()\n}"
        #expect(CodeFormatter.dedent(input) == input)
    }

    /// A single indented line is dedented to the margin.
    @Test func dedentHandlesASingleLine() {
        #expect(CodeFormatter.dedent("      hello") == "hello")
    }

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

    // MARK: - tidy

    /// `tidy` routes JSON through the JSON re-indenter…
    @Test func tidyFormatsJSONForTheJSONLanguage() {
        #expect(CodeFormatter.tidy(#"{"a":1}"#, language: .json) == "{\n  \"a\": 1\n}")
    }

    /// A brace language (Swift) is structurally re-indented — fixing a body that dedent
    /// alone could not (already flush-left, but mis-indented inside the braces).
    @Test func tidyReindentsBraceLanguages() {
        let input = "struct A {\nlet x = 1\n}"
        #expect(CodeFormatter.tidy(input, language: .swift) == "struct A {\n  let x = 1\n}")
    }

    /// Malformed JSON under the JSON language falls back to a harmless dedent rather
    /// than mangling the user's text.
    @Test func tidyFallsBackToDedentForBrokenJSON() {
        let broken = "    {not valid json"
        #expect(CodeFormatter.tidy(broken, language: .json) == "{not valid json")
    }

    // MARK: - reindent (brace/tag languages)

    /// JSX with multiline attributes re-indents to two spaces. The `>` inside the
    /// `() => …` arrow is nested in the attribute's braces, so it is *not* mistaken for
    /// the tag's closing `>` — the failure mode that breaks naive angle-bracket counters.
    @Test func tidyReindentsJSXWithArrowAttributes() {
        let input =
            "<Button\n        variant=\"contained\"\n        onClick={() => save()}\n    >\n        Cancel\n    </Button>"
        let expected =
            "<Button\n  variant=\"contained\"\n  onClick={() => save()}\n>\n  Cancel\n</Button>"
        #expect(CodeFormatter.tidy(input, language: .javascript) == expected)
    }

    /// A backtick template literal spans lines: its interior lines are string content,
    /// so they must be emitted verbatim (leading whitespace untouched) and a `{` inside
    /// the template must not indent the code after the literal closes.
    @Test func tidyPreservesTemplateLiteralBodies() {
        let input =
            "function f() {\nconst s = `line one\n      keep me   {not a brace}\n`\nreturn s\n}"
        let expected =
            "function f() {\n  const s = `line one\n      keep me   {not a brace}\n`\n  return s\n}"
        #expect(CodeFormatter.tidy(input, language: .javascript) == expected)
    }

    /// A Swift triple-quoted string spans lines the same way: its body is emitted
    /// verbatim and the `{` inside it does not shift the trailing `}`.
    @Test func tidyPreservesSwiftTripleQuoteBodies() {
        let input = "func f() {\nlet s = \"\"\"\n  { indented content\n\"\"\"\n}"
        let expected = "func f() {\n  let s = \"\"\"\n  { indented content\n\"\"\"\n}"
        #expect(CodeFormatter.tidy(input, language: .swift) == expected)
    }

    /// Reindent is idempotent even across a multi-line literal: a second pass over the
    /// tidied output is a no-op (the verbatim body never drifts).
    @Test func tidyIsIdempotentAcrossMultilineStrings() {
        let input =
            "function f() {\nconst s = `line one\n      keep me   {not a brace}\n`\nreturn s\n}"
        let once = CodeFormatter.tidy(input, language: .javascript)
        #expect(CodeFormatter.tidy(once, language: .javascript) == once)
    }

    /// A backtick closed on the same line it opened is *not* multi-line: the code after
    /// it re-indents normally, so the carry-across state never leaks.
    @Test func tidyReindentsCodeAfterASingleLineBacktick() {
        let input = "const a = `x`\nif (a) {\nb()\n}"
        let expected = "const a = `x`\nif (a) {\n  b()\n}"
        #expect(CodeFormatter.tidy(input, language: .javascript) == expected)
    }

    /// Go re-indents with tabs (gofmt's unit) and is fixed even when already flush-left
    /// — the case dedent cannot help because there is no shared margin to strip.
    @Test func tidyReindentsGoWithTabs() {
        let input = "func add(a, b int) int {\nreturn a + b\n}"
        #expect(
            CodeFormatter.tidy(input, language: .go)
                == "func add(a, b int) int {\n\treturn a + b\n}")
    }

    /// In a non-markup brace language, `<`/`>` are comparisons or generics, never tags:
    /// `Array<number>` and `a < b && c > d` must not shift the indentation.
    @Test func tidyDoesNotMistakeGenericsOrComparisonsForTags() {
        let input =
            "function f() {\nconst x: Array<number> = []\nif (a < b && c > d) {\nreturn x\n}\n}"
        let expected =
            "function f() {\n  const x: Array<number> = []\n  if (a < b && c > d) {\n    return x\n  }\n}"
        #expect(CodeFormatter.tidy(input, language: .typescript) == expected)
    }

    /// Re-indenting is idempotent: tidying already-tidy output changes nothing (the
    /// guard the Format command and auto-on-paste rely on to avoid a redundant edit).
    @Test func tidyIsIdempotent() {
        let tidied = "function f() {\n  return 1\n}"
        #expect(CodeFormatter.tidy(tidied, language: .javascript) == tidied)
    }

    // MARK: - dedent-only / leave-alone families

    /// Python's block structure is its indentation, not brackets, so tidy only strips the
    /// shared margin (a snippet copied from inside a class) and never re-indents it.
    @Test func tidyDedentsPythonAndNeverReindents() {
        let input = "    def f():\n        return 1"
        #expect(CodeFormatter.tidy(input, language: .python) == "def f():\n    return 1")
    }

    /// In a diff the leading `+`/`-`/space is data, so tidy leaves it untouched.
    @Test func tidyLeavesDiffUntouched() {
        let input = " context line\n-removed\n+added"
        #expect(CodeFormatter.tidy(input, language: .diff) == input)
    }
}
