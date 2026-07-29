import Foundation

extension CodeFormatter {
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
}
