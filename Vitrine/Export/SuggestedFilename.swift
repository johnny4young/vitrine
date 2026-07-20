import Foundation

/// Derives the save panel's proposed filename from what the snapshot actually
/// shows, replacing the fixed `vitrine.png` so exports land pre-named after
/// their content.
///
/// Precedence, most specific first:
///   1. The metadata filename chip, without its extension
///      (`ContentView.swift` → `ContentView`) — the user already named the code.
///   2. The first declared identifier in the code (`func`, `class`, `struct`,
///      `def`, `fn`, `function`, …), prefixed `vitrine-` so an export folder
///      still groups by app.
///   3. The plain `vitrine` fallback (empty code, terminal output, images).
///
/// Pure and deterministic (no AppKit, no state) so the mapping is unit-testable;
/// the extension is appended by the caller from the encoded payload.
enum SuggestedFilename {
    /// The proposed basename (no extension) for exporting `config`.
    static func basename(for config: SnapshotConfig) -> String {
        if let filename = config.metadata.filename {
            let stem = (filename as NSString).lastPathComponent
            let withoutExtension = (stem as NSString).deletingPathExtension
            let cleaned = sanitized(withoutExtension.isEmpty ? stem : withoutExtension)
            if !cleaned.isEmpty { return cleaned }
        }
        if config.language != .terminal, let declared = firstDeclaredIdentifier(in: config.code) {
            return "vitrine-\(declared)"
        }
        return "vitrine"
    }

    /// The first identifier introduced by a declaration keyword common across the
    /// advertised languages, or `nil` when none is found in the first matches.
    private static func firstDeclaredIdentifier(in code: String) -> String? {
        let pattern =
            #"\b(?:func|fn|def|function|class|struct|enum|protocol|interface|trait|impl|module)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        guard let match = regex.firstMatch(in: code, range: range),
            let identifierRange = Range(match.range(at: 1), in: code)
        else { return nil }
        return String(code[identifierRange])
    }

    /// Makes a candidate safe as a filename stem: path separators and colons
    /// become hyphens, whitespace runs collapse to one hyphen, leading dots are
    /// dropped (no accidental hidden files), and the result is length-capped.
    private static func sanitized(_ candidate: String) -> String {
        var result = ""
        for character in candidate.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character == "/" || character == ":" || character == "\\" {
                result.append("-")
            } else if character.isWhitespace {
                if !result.hasSuffix("-") { result.append("-") }
            } else if !character.isNewline {
                result.append(character)
            }
        }
        while result.hasPrefix(".") { result.removeFirst() }
        return String(result.prefix(64))
    }

    /// A human-readable header-title suggestion for `config`, or `nil`
    /// when nothing meaningful can be inferred — the seam behind the inspector's
    /// "suggest title" affordance.
    ///
    /// Unlike `basename`, this is display text: the filename chip keeps its extension
    /// (`ContentView.swift` *is* a good title) and an inferred identifier carries no
    /// `vitrine-` prefix. Terminal output and plain images yield `nil` rather than a
    /// generic label the user would just delete.
    static func suggestedTitle(for config: SnapshotConfig) -> String? {
        if let filename = config.metadata.filename {
            let stem = (filename as NSString).lastPathComponent
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !stem.isEmpty { return String(stem.prefix(64)) }
        }
        guard config.language != .terminal else { return nil }
        return firstDeclaredIdentifier(in: config.code)
    }
}
