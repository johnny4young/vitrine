extension CodeFormatter {
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
