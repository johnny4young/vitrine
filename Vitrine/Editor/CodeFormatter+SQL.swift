import Foundation

extension CodeFormatter {
    /// Pretty-prints a SQL statement by tokenizing it first, then placing major clauses,
    /// joins, predicates, and top-level select/set items on readable lines. The lexer
    /// preserves quoted strings and identifiers, PostgreSQL dollar-quoted bodies,
    /// bracketed identifiers, line/block comments, and common parameter forms exactly.
    /// Keyword casing is never changed.
    ///
    /// Returns `nil` when the input does not begin with a recognized SQL statement, a
    /// quote/comment is unterminated, or parentheses are unbalanced. That conservative
    /// contract lets callers fall back to dedent instead of reshaping uncertain text.
    nonisolated static func formatSQL(_ code: String) -> String? {
        enum Token {
            case word(raw: String, upper: String)
            case opaque(String)
            case lineComment(String)
            case blockComment(String)
            case symbol(Character)

            var raw: String {
                switch self {
                case .word(let raw, _), .opaque(let raw), .lineComment(let raw),
                    .blockComment(let raw):
                    raw
                case .symbol(let character): String(character)
                }
            }

            var upperWord: String? {
                guard case .word(_, let upper) = self else { return nil }
                return upper
            }
        }

        enum ClauseKind {
            case selectList
            case setList
            case major
            case join
            case predicate
            case logical
        }

        let input = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let characters = Array(input)

        func isWordStart(_ character: Character) -> Bool {
            character.isLetter || character == "_"
        }
        func isWordBody(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "$"
        }
        func starts(with needle: [Character], at index: Int) -> Bool {
            guard index + needle.count <= characters.count else { return false }
            return characters[index..<(index + needle.count)].elementsEqual(needle)
        }
        func quotedEnd(from start: Int, quote: Character) -> Int? {
            var index = start + 1
            while index < characters.count {
                if characters[index] == quote {
                    if index + 1 < characters.count, characters[index + 1] == quote {
                        index += 2
                        continue
                    }
                    return index + 1
                }
                if characters[index] == "\\", index + 1 < characters.count {
                    index += 2
                } else {
                    index += 1
                }
            }
            return nil
        }

        var tokens: [Token] = []
        var cursor = 0
        while cursor < characters.count {
            let character = characters[cursor]
            if character.isWhitespace {
                cursor += 1
                continue
            }
            if character == "-", cursor + 1 < characters.count, characters[cursor + 1] == "-" {
                let start = cursor
                cursor += 2
                while cursor < characters.count, !characters[cursor].isNewline { cursor += 1 }
                tokens.append(.lineComment(String(characters[start..<cursor])))
                continue
            }
            if character == "/", cursor + 1 < characters.count, characters[cursor + 1] == "*" {
                let start = cursor
                var depth = 1
                cursor += 2
                while cursor < characters.count, depth > 0 {
                    if cursor + 1 < characters.count, characters[cursor] == "/",
                        characters[cursor + 1] == "*"
                    {
                        depth += 1
                        cursor += 2
                    } else if cursor + 1 < characters.count, characters[cursor] == "*",
                        characters[cursor + 1] == "/"
                    {
                        depth -= 1
                        cursor += 2
                    } else {
                        cursor += 1
                    }
                }
                guard depth == 0 else { return nil }
                tokens.append(.blockComment(String(characters[start..<cursor])))
                continue
            }
            if character == "'" || character == "\"" || character == "`" {
                let start = cursor
                guard let end = quotedEnd(from: cursor, quote: character) else { return nil }
                cursor = end
                tokens.append(.opaque(String(characters[start..<cursor])))
                continue
            }
            if character == "[" {
                let start = cursor
                cursor += 1
                var closed = false
                while cursor < characters.count {
                    if characters[cursor] == "]" {
                        if cursor + 1 < characters.count, characters[cursor + 1] == "]" {
                            cursor += 2
                            continue
                        }
                        cursor += 1
                        closed = true
                        break
                    }
                    cursor += 1
                }
                guard closed else { return nil }
                tokens.append(.opaque(String(characters[start..<cursor])))
                continue
            }
            if character == "$" {
                var delimiterEnd = cursor + 1
                while delimiterEnd < characters.count,
                    characters[delimiterEnd].isLetter || characters[delimiterEnd].isNumber
                        || characters[delimiterEnd] == "_"
                {
                    delimiterEnd += 1
                }
                if delimiterEnd < characters.count, characters[delimiterEnd] == "$" {
                    let delimiter = Array(characters[cursor...delimiterEnd])
                    let start = cursor
                    cursor = delimiterEnd + 1
                    while cursor < characters.count, !starts(with: delimiter, at: cursor) {
                        cursor += 1
                    }
                    guard cursor < characters.count else { return nil }
                    cursor += delimiter.count
                    tokens.append(.opaque(String(characters[start..<cursor])))
                    continue
                }
                if cursor + 1 < characters.count, characters[cursor + 1].isNumber {
                    let start = cursor
                    cursor += 2
                    while cursor < characters.count, characters[cursor].isNumber { cursor += 1 }
                    tokens.append(.opaque(String(characters[start..<cursor])))
                    continue
                }
            }
            if character == "?", cursor + 1 < characters.count,
                characters[cursor + 1] == "?" || characters[cursor + 1] == "&"
                    || characters[cursor + 1] == "|"
            {
                tokens.append(.opaque(String(characters[cursor...(cursor + 1)])))
                cursor += 2
                continue
            }
            let isNamedParameter =
                (character == ":" && cursor + 1 < characters.count
                    && (characters[cursor + 1] == ":" || isWordBody(characters[cursor + 1])))
                || (character == "@" && cursor + 1 < characters.count
                    && (characters[cursor + 1] == "@" || isWordBody(characters[cursor + 1])))
                || character == "?"
            if isNamedParameter {
                let start = cursor
                cursor += 1
                if character == ":", cursor < characters.count, characters[cursor] == ":" {
                    cursor += 1
                } else if character == "@", cursor < characters.count, characters[cursor] == "@" {
                    cursor += 1
                    while cursor < characters.count, isWordBody(characters[cursor]) { cursor += 1 }
                } else {
                    while cursor < characters.count, isWordBody(characters[cursor]) { cursor += 1 }
                }
                tokens.append(.opaque(String(characters[start..<cursor])))
                continue
            }
            if isWordStart(character) {
                let start = cursor
                cursor += 1
                while cursor < characters.count, isWordBody(characters[cursor]) { cursor += 1 }
                let raw = String(characters[start..<cursor])
                let quoteStart: Int? =
                    if cursor < characters.count, "'\"`".contains(characters[cursor]) {
                        cursor
                    } else if raw.uppercased() == "U", cursor + 1 < characters.count,
                        characters[cursor] == "&", "'\"".contains(characters[cursor + 1])
                    {
                        cursor + 1
                    } else {
                        nil
                    }
                if let quoteStart {
                    guard let end = quotedEnd(from: quoteStart, quote: characters[quoteStart])
                    else {
                        return nil
                    }
                    cursor = end
                    tokens.append(.opaque(String(characters[start..<cursor])))
                    continue
                }
                tokens.append(.word(raw: raw, upper: raw.uppercased()))
                continue
            }
            if character.isNumber {
                let start = cursor
                cursor += 1
                while cursor < characters.count {
                    let numericCharacter = characters[cursor]
                    guard
                        numericCharacter.isNumber || numericCharacter == "."
                            || numericCharacter == "_" || numericCharacter.isLetter
                    else { break }
                    cursor += 1
                    if numericCharacter == "e" || numericCharacter == "E",
                        cursor < characters.count,
                        characters[cursor] == "+" || characters[cursor] == "-"
                    {
                        cursor += 1
                    }
                }
                tokens.append(.opaque(String(characters[start..<cursor])))
                continue
            }
            if "(),;.".contains(character) {
                tokens.append(.symbol(character))
                cursor += 1
                continue
            }

            let start = cursor
            cursor += 1
            while cursor < characters.count,
                !characters[cursor].isWhitespace && !isWordStart(characters[cursor])
                    && !characters[cursor].isNumber && !"'\"`[](),;.".contains(characters[cursor])
                    && characters[cursor] != "$" && characters[cursor] != ":"
                    && characters[cursor] != "@" && characters[cursor] != "?"
                    && !(characters[cursor] == "-" && cursor + 1 < characters.count
                        && characters[cursor + 1] == "-")
                    && !(characters[cursor] == "/" && cursor + 1 < characters.count
                        && characters[cursor + 1] == "*")
            {
                cursor += 1
            }
            tokens.append(.opaque(String(characters[start..<cursor])))
        }

        let statementStarts: Set<String> = [
            "ALTER", "CREATE", "DELETE", "DROP", "INSERT", "MERGE", "SELECT", "UPDATE", "WITH",
        ]
        guard let firstWord = tokens.compactMap(\.upperWord).first,
            statementStarts.contains(firstWord)
        else { return nil }

        let phrases: [([String], ClauseKind)] = [
            (["LEFT", "OUTER", "JOIN"], .join), (["RIGHT", "OUTER", "JOIN"], .join),
            (["FULL", "OUTER", "JOIN"], .join), (["INSERT", "INTO"], .major),
            (["DELETE", "FROM"], .major), (["GROUP", "BY"], .major),
            (["ORDER", "BY"], .major), (["UNION", "ALL"], .major),
            (["LEFT", "JOIN"], .join), (["RIGHT", "JOIN"], .join),
            (["FULL", "JOIN"], .join), (["INNER", "JOIN"], .join),
            (["CROSS", "JOIN"], .join), (["SELECT"], .selectList),
            (["UPDATE"], .major), (["SET"], .setList), (["FROM"], .major),
            (["WHERE"], .major), (["GROUP"], .major), (["HAVING"], .major),
            (["ORDER"], .major), (["LIMIT"], .major), (["OFFSET"], .major),
            (["FETCH"], .major), (["VALUES"], .major), (["RETURNING"], .setList),
            (["UNION"], .major), (["INTERSECT"], .major), (["EXCEPT"], .major),
            (["JOIN"], .join), (["ON"], .predicate), (["AND"], .logical),
            (["OR"], .logical),
        ]

        func clause(at index: Int) -> (length: Int, kind: ClauseKind)? {
            for phrase in phrases {
                guard index + phrase.0.count <= tokens.count else { continue }
                let matches = phrase.0.enumerated().allSatisfy { offset, word in
                    tokens[index + offset].upperWord == word
                }
                if matches { return (phrase.0.count, phrase.1) }
            }
            return nil
        }

        var lines: [String] = []
        var current = ""
        var parenthesisDepth = 0
        var listDepth: Int?
        var index = 0

        func flushLine() {
            var line = current
            while line.last == " " || line.last == "\t" { line.removeLast() }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { lines.append(line) }
            current = ""
        }
        func startLine(indent: Int) {
            flushLine()
            current = String(repeating: "  ", count: max(0, indent))
        }
        func append(_ raw: String) {
            let meaningful = current.trimmingCharacters(in: .whitespaces)
            if meaningful.isEmpty {
                current += raw
                return
            }
            let noLeadingSpace =
                raw == "(" || raw == ")" || raw == "," || raw == ";" || raw == "."
            let noTrailingSpace = current.last == "(" || current.last == "."
            if !noLeadingSpace && !noTrailingSpace { current += " " }
            current += raw
        }

        while index < tokens.count {
            if let matched = clause(at: index) {
                switch matched.kind {
                case .selectList:
                    startLine(indent: parenthesisDepth)
                    listDepth = parenthesisDepth
                case .setList:
                    startLine(indent: parenthesisDepth)
                    listDepth = parenthesisDepth
                case .major:
                    startLine(indent: parenthesisDepth)
                    listDepth = nil
                case .join:
                    startLine(indent: parenthesisDepth)
                    listDepth = nil
                case .predicate, .logical:
                    startLine(indent: parenthesisDepth + 1)
                }
                let raw = tokens[index..<(index + matched.length)].map(\.raw).joined(separator: " ")
                append(raw)
                switch matched.kind {
                case .selectList, .setList:
                    startLine(indent: parenthesisDepth + 1)
                default: break
                }
                index += matched.length
                continue
            }

            switch tokens[index] {
            case .lineComment(let raw):
                append(raw)
                startLine(
                    indent: (listDepth == parenthesisDepth)
                        ? parenthesisDepth + 1 : parenthesisDepth)
            case .blockComment(let raw): append(raw)
            case .symbol("("):
                append("(")
                parenthesisDepth += 1
            case .symbol(")"):
                guard parenthesisDepth > 0 else { return nil }
                parenthesisDepth -= 1
                append(")")
            case .symbol(","):
                append(",")
                if listDepth == parenthesisDepth { startLine(indent: parenthesisDepth + 1) }
            case .symbol(";"):
                append(";")
                startLine(indent: 0)
                listDepth = nil
            default: append(tokens[index].raw)
            }
            index += 1
        }
        guard parenthesisDepth == 0 else { return nil }
        flushLine()
        return lines.joined(separator: "\n")
    }
}
