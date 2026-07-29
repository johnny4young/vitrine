import Testing

@testable import Vitrine

@Suite("Code formatter — brace and tag indentation")
struct CodeFormatterReindentTests {
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
    /// the case dedent cannot help because there is no shared margin to strip.
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
}
