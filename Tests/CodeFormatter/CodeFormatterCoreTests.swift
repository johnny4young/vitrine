import Testing

@testable import Vitrine

@Suite("Code formatter — routing and whitespace")
struct CodeFormatterCoreTests {

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

    // MARK: - tidy

    /// `tidy` routes JSON through the JSON re-indenter…
    @Test func tidyFormatsJSONForTheJSONLanguage() {
        #expect(CodeFormatter.tidy(#"{"a":1}"#, language: .json) == "{\n  \"a\": 1\n}")
    }

    /// HTML routes through the structural markup formatter, making minified one-line
    /// pastes readable before they render.
    @Test func tidyPrettyPrintsCompactHTML() {
        let input = "<main><h1>Vitrine</h1><p>Local by design.</p></main>"
        let expected = """
            <main>
              <h1>Vitrine</h1>
              <p>Local by design.</p>
            </main>
            """
        #expect(CodeFormatter.tidy(input, language: .html) == expected)
    }

    /// SQL routes through its tokenizer-backed formatter instead of the previous dedent-
    /// only path.
    @Test func tidyPrettyPrintsCompactSQL() {
        let expected = """
            SELECT
              id,
              name
            FROM users
            WHERE active = TRUE;
            """
        #expect(
            CodeFormatter.tidy("SELECT id,name FROM users WHERE active=TRUE;", language: .sql)
                == expected)
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

    // MARK: - smart trim

    /// Blank lines pasted above and below a snippet read as accidental padding on top of
    /// the canvas's own, so trim drops them.
    @Test func trimDropsLeadingAndTrailingBlankLines() {
        let input = "\n  \nlet x = 1\nprint(x)\n\n\t\n"
        #expect(CodeFormatter.trimmed(input, language: .swift) == "let x = 1\nprint(x)")
    }

    /// Trailing spaces/tabs on each line are invisible in the render but shift a
    /// line-width-based layout, so trim strips them for code languages.
    @Test func trimStripsPerLineTrailingWhitespace() {
        let input = "let x = 1   \nprint(x)\t"
        #expect(CodeFormatter.trimmed(input, language: .swift) == "let x = 1\nprint(x)")
    }

    /// Two trailing spaces are a hard line break in Markdown, so line interiors stay
    /// byte-for-byte intact for leave-alone formats — only surrounding blanks drop.
    @Test func trimPreservesMarkdownHardBreaksButDropsSurroundingBlanks() {
        let input = "\nline one  \nline two\n\n"
        #expect(
            CodeFormatter.trimmed(input, language: .markdown) == "line one  \nline two")
    }

    /// The whole pipeline: tidy now trims, so a paste with stray padding lands even.
    @Test func tidyTrimsBlankPaddingAroundReindentedCode() {
        let input = "\nstruct A {\nlet x = 1   \n}\n\n"
        #expect(CodeFormatter.tidy(input, language: .swift) == "struct A {\n  let x = 1\n}")
    }

    /// Trim (and tidy-with-trim) stays idempotent, and an all-blank snippet collapses
    /// to empty rather than trapping.
    @Test func trimIsIdempotentAndHandlesDegenerateInput() {
        let once = CodeFormatter.trimmed("\n\na = 1\n\n", language: .python)
        #expect(CodeFormatter.trimmed(once, language: .python) == once)
        #expect(CodeFormatter.trimmed("\n \t\n", language: .swift) == "")
        #expect(CodeFormatter.trimmed("", language: .swift) == "")
    }
}
