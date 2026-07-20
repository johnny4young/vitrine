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

    /// Structurally pretty-prints a JSON object or array with a two-space indent,
    /// **preserving key order**. Returns `nil` when the input is not a single JSON
    /// value, so a non-JSON paste is never mangled. The scan is string- and
    /// escape-aware, so braces, brackets, or commas inside string literals are left
    /// untouched, and empty containers collapse to `{}` / `[]`.
    nonisolated static func formatJSON(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let head = trimmed.first, head == "{" || head == "[" else { return nil }
        // Validate first so non-JSON (or truncated JSON) is rejected, not reshaped.
        guard let data = trimmed.data(using: .utf8),
            (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return nil }

        let chars = Array(trimmed)
        var out = ""
        out.reserveCapacity(chars.count + chars.count / 4)
        var depth = 0
        var inString = false
        var escaped = false
        let indentUnit = "  "

        func newline(_ level: Int) {
            out.append("\n")
            out.append(String(repeating: indentUnit, count: level))
        }
        func isStructuralWhitespace(_ c: Character) -> Bool {
            c == " " || c == "\t" || c == "\n" || c == "\r"
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                i += 1
                continue
            }

            switch c {
            case "\"":
                inString = true
                out.append(c)
            case "{", "[":
                // Collapse an empty container ({ }, [ ]) onto a single line.
                var j = i + 1
                while j < chars.count, isStructuralWhitespace(chars[j]) { j += 1 }
                let close: Character = c == "{" ? "}" : "]"
                if j < chars.count, chars[j] == close {
                    out.append(c)
                    out.append(close)
                    i = j + 1
                    continue
                }
                out.append(c)
                depth += 1
                newline(depth)
            case "}", "]":
                depth = max(0, depth - 1)
                newline(depth)
                out.append(c)
            case ",":
                out.append(c)
                newline(depth)
            case ":":
                out.append(c)
                out.append(" ")
            default:
                if !isStructuralWhitespace(c) { out.append(c) }
            }
            i += 1
        }
        return out
    }

    /// Expands compact HTML/XML into a two-space-indented element hierarchy without
    /// using a DOM parser (which can reorder attributes or normalize entities). The
    /// tokenizer is quote-aware, validates balanced element names, keeps leaf text
    /// inline, and preserves comments, declarations, and processing instructions.
    ///
    /// Returns `nil` for malformed markup and for constructs where inserted whitespace
    /// could change meaning: mixed text + child elements, multi-line text nodes, and
    /// raw-text containers (`script`, `style`, `pre`, `textarea`). The caller then uses
    /// the existing line-only tag re-indenter, so Format Code never corrupts content.
    nonisolated static func formatMarkup(_ code: String) -> String? {
        enum Token {
            case opening(name: String, raw: String)
            case closing(name: String, raw: String)
            case standalone(raw: String)
            case text(String)
        }

        let input = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.first == "<" else { return nil }
        let characters = Array(input)
        let voidElements: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
            "param", "source", "track", "wbr",
        ]
        let rawTextElements: Set<String> = ["pre", "script", "style", "textarea"]

        func starts(with needle: String, at index: Int) -> Bool {
            let expected = Array(needle)
            guard index + expected.count <= characters.count else { return false }
            return characters[index..<(index + expected.count)].elementsEqual(expected)
        }

        func scanTagEnd(from start: Int, declaration: Bool = false) -> Int? {
            var quote: Character?
            var internalSubsetDepth = 0
            var index = start + 1
            while index < characters.count {
                let character = characters[index]
                if let activeQuote = quote {
                    if character == activeQuote { quote = nil }
                } else {
                    switch character {
                    case "\"", "'": quote = character
                    case "[" where declaration: internalSubsetDepth += 1
                    case "]" where declaration:
                        internalSubsetDepth = max(0, internalSubsetDepth - 1)
                    case ">" where internalSubsetDepth == 0: return index
                    default: break
                    }
                }
                index += 1
            }
            return nil
        }

        func elementName(in raw: String, closing: Bool) -> String? {
            let offset = closing ? 2 : 1
            guard raw.count > offset else { return nil }
            let body = raw.dropFirst(offset)
            let name = body.prefix {
                $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ":"
            }
            guard !name.isEmpty, name.first?.isLetter == true || name.first == "_" else {
                return nil
            }
            return name.lowercased()
        }

        var tokens: [Token] = []
        var cursor = 0
        while cursor < characters.count {
            guard characters[cursor] == "<" else {
                let start = cursor
                while cursor < characters.count, characters[cursor] != "<" { cursor += 1 }
                tokens.append(.text(String(characters[start..<cursor])))
                continue
            }

            if starts(with: "<!--", at: cursor) {
                var end = cursor + 4
                while end + 2 < characters.count, !starts(with: "-->", at: end) { end += 1 }
                guard end + 2 < characters.count else { return nil }
                tokens.append(.standalone(raw: String(characters[cursor..<(end + 3)])))
                cursor = end + 3
                continue
            }
            if starts(with: "<![CDATA[", at: cursor) {
                var end = cursor + 9
                while end + 2 < characters.count, !starts(with: "]]>", at: end) { end += 1 }
                guard end + 2 < characters.count else { return nil }
                // CDATA is text, not a structural declaration. Treat it as a text
                // token so a leaf can stay byte-for-byte inline and a multi-line or
                // mixed-content use takes the same conservative nil fallback as text.
                tokens.append(.text(String(characters[cursor..<(end + 3)])))
                cursor = end + 3
                continue
            }
            if starts(with: "<?", at: cursor) {
                var end = cursor + 2
                while end + 1 < characters.count, !starts(with: "?>", at: end) { end += 1 }
                guard end + 1 < characters.count else { return nil }
                tokens.append(.standalone(raw: String(characters[cursor..<(end + 2)])))
                cursor = end + 2
                continue
            }

            let declaration = starts(with: "<!", at: cursor)
            guard let end = scanTagEnd(from: cursor, declaration: declaration) else { return nil }
            let raw = String(characters[cursor...end])
            cursor = end + 1
            if declaration {
                tokens.append(.standalone(raw: raw))
                continue
            }

            let closing = raw.hasPrefix("</")
            guard let name = elementName(in: raw, closing: closing) else { return nil }
            if closing {
                tokens.append(.closing(name: name, raw: raw))
            } else if raw.dropLast().trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/")
                || voidElements.contains(name)
            {
                tokens.append(.standalone(raw: raw))
            } else {
                guard !rawTextElements.contains(name) else { return nil }
                tokens.append(.opening(name: name, raw: raw))
            }
        }

        var validationStack: [String] = []
        for token in tokens {
            switch token {
            case .opening(let name, _): validationStack.append(name)
            case .closing(let name, _):
                guard validationStack.popLast() == name else { return nil }
            case .standalone, .text: break
            }
        }
        guard validationStack.isEmpty else { return nil }

        var lines: [String] = []
        var depth = 0
        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .opening(let name, let raw):
                if index + 2 < tokens.count,
                    case .text(let text) = tokens[index + 1],
                    !text.contains(where: \Character.isNewline),
                    case .closing(let closingName, let closingRaw) = tokens[index + 2],
                    name == closingName
                {
                    lines.append(String(repeating: "  ", count: depth) + raw + text + closingRaw)
                    index += 3
                    continue
                }
                lines.append(String(repeating: "  ", count: depth) + raw)
                depth += 1
            case .closing(_, let raw):
                depth = max(0, depth - 1)
                lines.append(String(repeating: "  ", count: depth) + raw)
            case .standalone(let raw):
                lines.append(String(repeating: "  ", count: depth) + raw)
            case .text(let text):
                guard text.allSatisfy(\Character.isWhitespace) else { return nil }
            }
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    /// Re-indents `code` by recomputing each line's leading whitespace from its nesting
    /// depth: `{}` `()` `[]` for every brace/tag language, plus `<tag>` / `</tag>` /
    /// `<tag/>` when `tags` is true (JSX/HTML). String and comment bodies are masked
    /// first, so a bracket or angle inside `"…"`, `'…'`, a backtick template, `//`, or
    /// `/* … */` never miscounts — including the `>` in an arrow `() => x`, which sits
    /// inside the attribute's `{…}` (bracket depth > 0) and so is not read as a tag
    /// close. Token order on each line is preserved; only indentation changes, and the
    /// result is idempotent.
    nonisolated static func reindent(_ code: String, tags: Bool, indent: String) -> String {
        let rawLines = code.components(separatedBy: "\n")
        var depth = 0
        var inOpenTag = false
        var tagBaseDepth = 0
        var inBlockComment = false
        // Multi-line string state carried across lines (like `inBlockComment`): a
        // backtick template literal and a Swift/Kotlin/Scala triple-quoted string are
        // the only string forms that legally span lines. `"`/`'` stay line-local so an
        // unterminated one (a Rust lifetime `'a`, a stray apostrophe) cannot poison the
        // following lines — the documented heuristic limit above.
        var multilineBacktick = false
        var inTripleQuote = false
        var out: [String] = []
        out.reserveCapacity(rawLines.count)

        // A `<Ident` opens a tag only at line start or right after one of these tokens;
        // otherwise `a < b` or `Array<T>` would be misread as a tag.
        func opensTag(_ m: [Character], at index: Int) -> Bool {
            var j = index - 1
            while j >= 0, m[j] == " " || m[j] == "\t" { j -= 1 }
            if j < 0 { return true }
            return "({[=>&|?:".contains(m[j])
        }

        for raw in rawLines {
            // Whether this line begins inside a multi-line string literal opened on an
            // earlier line — if so, its leading whitespace is string *content* and must
            // be emitted verbatim, never re-indented.
            let startedInString = multilineBacktick || inTripleQuote
            let chars = Array(raw)
            var masked = chars
            var k = 0
            // Seed the per-line scan from a carried-open backtick template.
            var stringQuote: Character? = multilineBacktick ? "`" : nil
            while k < chars.count {
                let c = chars[k]
                if inBlockComment {
                    masked[k] = " "
                    if c == "*", k + 1 < chars.count, chars[k + 1] == "/" {
                        masked[k + 1] = " "
                        k += 2
                        inBlockComment = false
                        continue
                    }
                    k += 1
                    continue
                }
                if inTripleQuote {
                    masked[k] = " "
                    if c == "\"", k + 2 < chars.count, chars[k + 1] == "\"", chars[k + 2] == "\"" {
                        masked[k + 1] = " "
                        masked[k + 2] = " "
                        k += 3
                        inTripleQuote = false
                        continue
                    }
                    k += 1
                    continue
                }
                if let quote = stringQuote {
                    masked[k] = " "
                    if c == "\\" {
                        if k + 1 < chars.count { masked[k + 1] = " " }
                        k += 2
                        continue
                    }
                    if c == quote { stringQuote = nil }
                    k += 1
                    continue
                }
                if c == "\"", k + 2 < chars.count, chars[k + 1] == "\"", chars[k + 2] == "\"" {
                    // A triple-quoted string (Swift/Kotlin/Scala) opens here; it may span
                    // lines, so its state is carried like a block comment.
                    inTripleQuote = true
                    masked[k] = " "
                    masked[k + 1] = " "
                    masked[k + 2] = " "
                    k += 3
                    continue
                }
                if c == "\"" || c == "'" || c == "`" {
                    stringQuote = c
                    masked[k] = " "
                    k += 1
                    continue
                }
                if c == "/", k + 1 < chars.count, chars[k + 1] == "/" {
                    for index in k..<chars.count { masked[index] = " " }
                    break
                }
                if c == "/", k + 1 < chars.count, chars[k + 1] == "*" {
                    masked[k] = " "
                    masked[k + 1] = " "
                    inBlockComment = true
                    k += 2
                    continue
                }
                k += 1
            }

            // Carry an unterminated backtick template into the next line; a `"`/`'`
            // left open is deliberately dropped (see the state declaration above).
            multilineBacktick = (stringQuote == "`")

            if startedInString {
                // This line's leading whitespace is string content: emit it byte-for-byte
                // rather than re-indenting it. The depth scan below still runs on the
                // masked line, so a literal that closes mid-line keeps brace counting
                // correct for the code that follows on the same line.
                out.append(raw)
            } else {
                let trimmed = String(raw.drop { $0 == " " || $0 == "\t" })
                let maskedStart =
                    masked.firstIndex { $0 != " " && $0 != "\t" }
                    .map { String(masked[$0...]) } ?? ""

                let renderDepth: Int
                if inOpenTag {
                    renderDepth =
                        (maskedStart.hasPrefix(">") || maskedStart.hasPrefix("/>"))
                        ? tagBaseDepth : tagBaseDepth + 1
                } else if maskedStart.hasPrefix("</")
                    || (maskedStart.first.map { "})]".contains($0) } ?? false)
                {
                    renderDepth = depth - 1
                } else {
                    renderDepth = depth
                }

                out.append(
                    trimmed.isEmpty
                        ? "" : String(repeating: indent, count: max(0, renderDepth)) + trimmed)
            }

            var i = 0
            var localBracket = 0
            while i < masked.count {
                let c = masked[i]
                if inOpenTag {
                    switch c {
                    case "{", "(", "[": localBracket += 1
                    case "}", ")", "]": localBracket = max(0, localBracket - 1)
                    case "/"
                    where localBracket == 0 && i + 1 < masked.count && masked[i + 1] == ">":
                        inOpenTag = false
                        depth = tagBaseDepth
                        i += 2
                        continue
                    case ">" where localBracket == 0:
                        inOpenTag = false
                        depth = tagBaseDepth + 1
                    default: break
                    }
                    i += 1
                    continue
                }
                switch c {
                case "{", "(", "[": depth += 1
                case "}", ")", "]": depth = max(0, depth - 1)
                case "<" where tags && i + 1 < masked.count && masked[i + 1] == "/":
                    depth = max(0, depth - 1)
                    i += 2
                    while i < masked.count, masked[i] != ">" { i += 1 }
                    i += 1
                    continue
                case "<"
                where tags && i + 1 < masked.count && masked[i + 1].isLetter
                    && opensTag(masked, at: i):
                    var j = i + 1
                    var lb = 0
                    var closed = false
                    var selfClosed = false
                    while j < masked.count {
                        let d = masked[j]
                        if d == "{" || d == "(" || d == "[" {
                            lb += 1
                        } else if d == "}" || d == ")" || d == "]" {
                            lb = max(0, lb - 1)
                        } else if lb == 0, d == "/", j + 1 < masked.count, masked[j + 1] == ">" {
                            closed = true
                            selfClosed = true
                            j += 2
                            break
                        } else if lb == 0, d == ">" {
                            closed = true
                            j += 1
                            break
                        }
                        j += 1
                    }
                    if closed {
                        if !selfClosed { depth += 1 }
                        i = j
                        continue
                    }
                    inOpenTag = true
                    tagBaseDepth = depth
                    i = masked.count
                    continue
                default: break
                }
                i += 1
            }
        }
        return out.joined(separator: "\n")
    }
}

extension Language {
    /// How ``CodeFormatter/tidy(_:language:)`` should tidy this language, picked so each
    /// gets the safe transform. Brace/tag languages re-indent from nesting;
    /// JSON gets its exact re-indent; whitespace/keyword-significant languages are only
    /// dedented (re-indenting them from brackets would corrupt the block structure); and
    /// formats where leading whitespace is data are left untouched.
    enum FormatStrategy {
        case json
        case markup
        case sql
        case reindentBraces
        case reindentTags
        case dedentOnly
        case leaveAlone
    }

    nonisolated var formatStrategy: FormatStrategy {
        switch self {
        case .json: .json
        case .html: .markup
        case .sql: .sql
        case .javascript, .typescript: .reindentTags
        case .swift, .go, .rust, .java, .kotlin, .c, .cpp, .csharp, .objectivec,
            .scala, .dart, .css, .scss, .php, .r, .perl, .graphql:
            .reindentBraces
        case .python, .yaml, .ruby, .haskell, .lua, .elixir, .bash, .toml,
            .dockerfile:
            .dedentOnly
        case .diff, .markdown, .terminal, .plaintext: .leaveAlone
        }
    }

    /// The indentation unit re-indenting emits: a tab for Go (gofmt's convention), two
    /// spaces otherwise (the web/JS norm and a safe neutral default for the rest).
    nonisolated var indentUnit: String {
        switch self {
        case .go: "\t"
        default: "  "
        }
    }
}
