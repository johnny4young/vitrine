import Foundation

/// Safe, formatter-free code tidying.
///
/// Vitrine is sandboxed, local, and ships no language toolchains, so it cannot run a
/// real per-language formatter (swift-format, Prettier, gofmt, …). `CodeFormatter`
/// instead applies transforms that need no external tool, routed per language so each
/// gets the safest one (see ``Language/formatStrategy``):
///
///   - ``reindent(_:tags:indent:)`` recomputes each line's indentation from bracket
///     (`{}` `()` `[]`) and — for JSX/HTML — tag nesting. It masks string and comment
///     bodies first, so the `>` in `() => x` or a `"}"` inside a literal never
///     miscounts. Used for brace/tag languages (Swift, Go, Rust, JS/TS, CSS, …), where
///     correct indentation *is* nesting depth.
///   - ``formatJSON(_:)`` structurally re-indents a JSON value, **preserving key
///     order** (which `JSONSerialization` would lose).
///   - ``formatMarkup(_:)`` expands compact HTML/XML into a readable hierarchy when
///     doing so cannot change text semantics; malformed, mixed-content, and raw-text
///     documents fall back to the existing line-based tag re-indenter.
///   - ``formatSQL(_:)`` tokenizes statements before laying out clauses, so quoted
///     values, identifiers, comments, and vendor parameter forms stay byte-for-byte
///     intact while minified queries become readable.
///   - ``dedent(_:)`` removes the uniform left margin a snippet picks up when copied
///     from deep inside a file. Used for whitespace/keyword-significant languages
///     (Python, YAML, Ruby, …) whose block structure is *not* in brackets, so
///     re-indenting them heuristically would corrupt the code.
///
/// It deliberately does **not** reflow source (no wrapping, no token moves) — only the
/// leading whitespace of each line changes, so the user's code is never restructured.
/// Multi-line string literals are preserved: a backtick template literal and a
/// Swift/Kotlin/Scala triple-quoted string carry their open state across lines, so
/// their interior lines are emitted verbatim (never re-indented) and braces inside
/// them do not shift nesting depth.
///
/// Heuristic limits (acceptable for a dependency-free display formatter): a Rust
/// lifetime (`&'a T`) sharing a line with a brace, and an attribute brace that spans
/// lines inside a JSX open tag, can mis-indent that line; four or more adjacent
/// quotes (`""""`) can be misread as a triple-quote opener.
enum CodeFormatter {
    /// Runs the bounded pure formatter away from the caller's actor. Swift 6.2 keeps
    /// ordinary async functions on their caller's executor, so the explicit
    /// `@concurrent` hop is what prevents a large interactive format from blocking
    /// AppKit's main actor. Cancellation is checked on both sides of the synchronous
    /// transform: callers can suppress obsolete results even though the formatter's
    /// one-megabyte input cap already bounds the CPU work itself.
    @concurrent
    nonisolated static func tidyConcurrently(
        _ code: String, language: Language
    ) async throws
        -> String
    {
        try Task.checkCancellation()
        let result = tidy(code, language: language)
        try Task.checkCancellation()
        return result
    }

    /// Tidies `code` for display by routing on the language's ``Language/formatStrategy``:
    /// brace/tag languages are structurally re-indented, JSON gets its exact re-indent,
    /// whitespace-significant languages are dedented, and formats where leading
    /// whitespace is data (diff, Markdown, plain text) are left untouched. Every route
    /// then passes through ``trimmed(_:language:)`` so a snippet pasted with stray blank
    /// lines or trailing spaces lands even and centered without a separate action
    /// (the Xnapper-style "smart trim"). The output is always valid and idempotent; a
    /// tidy input comes back unchanged.
    nonisolated static func tidy(_ code: String, language: Language) -> String {
        let routed =
            switch language.formatStrategy {
            case .json: formatJSON(code) ?? dedent(code)
            case .markup:
                formatMarkup(code) ?? reindent(code, tags: true, indent: language.indentUnit)
            case .sql: formatSQL(code) ?? dedent(code)
            case .reindentBraces: reindent(code, tags: false, indent: language.indentUnit)
            case .reindentTags: reindent(code, tags: true, indent: language.indentUnit)
            case .dedentOnly: dedent(code)
            case .leaveAlone: code
            }
        return trimmed(routed, language: language)
    }

    /// Evens out the whitespace around a snippet so the rendered card is balanced:
    /// leading and trailing blank lines are dropped (they read as accidental padding on
    /// top of the canvas's own), and each line's trailing spaces/tabs are stripped.
    ///
    /// Language-aware where trailing whitespace is *data*: for ``FormatStrategy/leaveAlone``
    /// formats (Markdown, where two trailing spaces are a hard line break; diff; plain
    /// text) only the surrounding blank lines are dropped and line interiors are left
    /// byte-for-byte intact. Idempotent, and never touches indentation or tokens.
    nonisolated static func trimmed(_ code: String, language: Language) -> String {
        func isBlank(_ line: String) -> Bool { line.allSatisfy { $0 == " " || $0 == "\t" } }
        var lines = code.components(separatedBy: "\n")
        // Pattern-match rather than `!=`: the synthesized Equatable is main-actor-
        // isolated under the module's default isolation, and this helper is nonisolated.
        if case .leaveAlone = language.formatStrategy {
        } else {
            lines = lines.map { line in
                var stripped = line
                while let last = stripped.last, last == " " || last == "\t" {
                    stripped.removeLast()
                }
                return stripped
            }
        }
        while let first = lines.first, isBlank(first) { lines.removeFirst() }
        while let last = lines.last, isBlank(last) { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// Removes the longest run of leading whitespace shared by every non-blank line
    /// (textwrap.dedent semantics). A block copied from inside a deeply-nested scope
    /// loses its uniform margin but keeps its internal structure. Tabs and spaces are
    /// compared literally (no tab-width assumptions); whitespace-only lines are
    /// emptied so no trailing indentation survives. Returns `code` unchanged when the
    /// lines share no common leading whitespace.
    nonisolated static func dedent(_ code: String) -> String {
        let lines = code.components(separatedBy: "\n")
        func leading(_ line: String) -> String {
            String(line.prefix { $0 == " " || $0 == "\t" })
        }
        func isBlank(_ line: String) -> Bool {
            line.allSatisfy { $0 == " " || $0 == "\t" }
        }

        var common: String?
        for line in lines where !isBlank(line) {
            let indent = leading(line)
            if let current = common {
                common = String(zip(current, indent).prefix { $0.0 == $0.1 }.map(\.0))
            } else {
                common = indent
            }
            if common?.isEmpty == true { return code }
        }

        guard let prefix = common, !prefix.isEmpty else { return code }
        return
            lines
            .map { line in
                // Empty whitespace-only lines first: a blank line longer than the
                // common prefix must collapse to "", not keep its leftover spaces.
                if isBlank(line) { return "" }
                if line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
                return line
            }
            .joined(separator: "\n")
    }
}
