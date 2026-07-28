import Foundation

extension CodeFormatter {
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
}
