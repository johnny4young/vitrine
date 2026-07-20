import Foundation

/// Best-effort content/language detection from clipboard text.
///
/// `detect(_:)` uses additive weighted keyword scoring and returns the highest
/// scoring language (or `.plaintext` when there is no signal), which is more
/// robust than ordered `if/else` for overlapping tokens (e.g. Swift vs Go `func`).
///
/// The detector layers two structural hints on top of that scoring so quick capture
/// understands common developer clipboard formats: Markdown code fences (which
/// often carry an explicit language in their info string) and file paths /
/// drop metadata (whose extension names the language). `interpret(_:)` combines
/// all of this into a single, unit-testable result the capture path consumes.
enum LanguageDetector {
    /// Returns `true` when the text looks like a single http(s) URL.
    static func isURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isNewline),
            let url = URL(string: trimmed),
            let scheme = url.scheme
        else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// Detects the most likely language via weighted keyword scoring.
    static func detect(_ raw: String) -> Language {
        // A bare http(s) URL is not source code: render it as plain text rather than
        // letting keyword scoring color it like a program (e.g. the digits in
        // `…/v0.1.0` highlighted as numeric literals). .
        if isURL(raw) { return .plaintext }
        // Terminal output carries ANSI escape codes; render it through the ANSI path
        // (colored by its own escapes) rather than scoring it as source code.
        if ANSIParser.containsANSI(raw) { return .terminal }
        let code = raw.lowercased()
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .plaintext
        }

        var scores: [Language: Int] = [:]
        func add(_ language: Language, _ signals: [(needle: String, weight: Int)]) {
            for signal in signals where code.contains(signal.needle) {
                scores[language, default: 0] += signal.weight
            }
        }

        add(
            .swift,
            [
                ("import swiftui", 3), ("import foundation", 3), ("@state", 3),
                ("guard let", 2), ("-> some view", 3), ("func ", 2), ("let ", 1), ("var ", 1),
            ])
        add(.go, [("package main", 3), ("func main(", 3), ("fmt.", 2), (":=", 2), ("import (", 2)])
        add(
            .python,
            [
                ("def ", 3), ("elif ", 2), ("import numpy", 2), ("__init__", 3),
                ("print(", 1), ("self.", 1),
            ])
        add(
            .javascript,
            [
                ("function ", 2), ("const ", 1), ("=>", 1), ("console.log", 2),
                ("require(", 2), ("document.", 2),
            ])
        add(
            .typescript,
            [
                ("interface ", 3), (": string", 2), (": number", 2),
                (": boolean", 2), ("export type", 3), ("implements ", 2),
            ])
        add(
            .sql,
            [
                ("select ", 2), ("insert into", 3), ("update ", 2), ("delete from", 3),
                (" where ", 2), (" join ", 2),
            ])
        add(.html, [("<!doctype", 3), ("<html", 3), ("</div>", 2), ("<body", 2), ("<span", 1)])
        add(
            .bash,
            [
                ("#!/bin/bash", 3), ("#!/bin/sh", 3), ("#!/usr/bin/env", 2), ("echo ", 1),
                ("fi\n", 1),
            ])

        // TypeScript subsumes the generic JavaScript signals.
        if let typescript = scores[.typescript], typescript > 0 {
            scores[.javascript] = (scores[.javascript] ?? 0) - 1
        }

        // Deterministic argmax: highest score wins, ties broken by raw value.
        let ranked = scores.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue
        }
        guard let best = ranked.first, best.value > 0 else { return .plaintext }
        return best.key
    }

    // MARK: - File extensions

    /// Reverse extension → language table. Each language's canonical extension is
    /// derived from `Language.fileExtension`; this dictionary additionally lists
    /// the common aliases that a single canonical value cannot express
    /// (`.yml`/`.yaml`, `.htm`/`.html`, the C/C++ family, `.tsx`/`.jsx`, …).
    ///
    /// Built once and shared; all keys are lowercased and dot-free so lookups can
    /// normalize the same way.
    private static let extensionMap: [String: Language] = {
        var map: [String: Language] = [:]
        // Canonical extensions first, so a language always at least resolves from
        // its own `fileExtension`.
        for language in Language.allCases {
            if let ext = language.fileExtension { map[ext] = language }
        }
        // Aliases and additional source extensions that do not round-trip to a
        // single canonical value.
        let aliases: [String: Language] = [
            "pyi": .python,
            "mjs": .javascript, "cjs": .javascript, "jsx": .javascript,
            "tsx": .typescript, "mts": .typescript, "cts": .typescript,
            "kts": .kotlin,
            "cc": .cpp, "cxx": .cpp, "hpp": .cpp, "hh": .cpp,
            "h": .objectivec, "mm": .objectivec,
            "rb": .ruby,
            "exs": .elixir,
            "lhs": .haskell,
            "rmd": .r,
            "pm": .perl,
            "phtml": .php,
            "htm": .html,
            "yml": .yaml,
            "bash": .bash, "zsh": .bash, "ksh": .bash,
            "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
            "patch": .diff,
            "txt": .plaintext, "text": .plaintext,
        ]
        map.merge(aliases) { current, _ in current }
        return map
    }()

    /// Maps a filename extension (with or without a leading dot, any case) to a
    /// language, or `nil` when it is empty or unrecognized.
    static func language(forFileExtension rawExtension: String) -> Language? {
        let key =
            rawExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .drop { $0 == "." }
        guard !key.isEmpty else { return nil }
        return extensionMap[String(key)]
    }

    /// Derives a language hint from a file path or URL string by its extension.
    /// Handles plain paths (`~/src/main.go`), `file://` URLs, and a
    /// special case for the extensionless `Dockerfile`. Returns `nil` when the
    /// text is not a single path-like token or its extension is unknown.
    static func language(forPath rawPath: String) -> Language? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        // A path that quick capture cares about is a single token with no spaces;
        // anything with whitespace or a newline is prose or source, not a path.
        guard !trimmed.isEmpty,
            !trimmed.contains(where: \.isWhitespace)
        else { return nil }

        // Resolve to the last path component, tolerating a `file://` URL.
        let lastComponent: String
        if let url = URL(string: trimmed), url.isFileURL {
            lastComponent = url.lastPathComponent
        } else {
            lastComponent = (trimmed as NSString).lastPathComponent
        }

        // Well-known extensionless filename (Highlight.js identifies Dockerfile by
        // name, not extension).
        if lastComponent.caseInsensitiveCompare("Dockerfile") == .orderedSame {
            return .dockerfile
        }

        // Otherwise an extension is required; a bare word with none (`README`,
        // `notes`) yields no hint, so single words are never treated as paths.
        let ext = (lastComponent as NSString).pathExtension
        guard !ext.isEmpty else { return nil }
        return language(forFileExtension: ext)
    }

    // MARK: - Clipboard interpretation

    /// A normalized view of clipboard text: the code to render, the best language
    /// hint, and how many distinct fenced code blocks were found. `blockCount`
    /// lets the capture path decide between rendering inline and deferring a
    /// multi-block paste to the editor.
    struct Interpretation: Equatable {
        var code: String
        var language: Language
        /// Number of fenced code blocks detected (0 when the text was not
        /// Markdown-fenced; 1 for a single block; >1 for several).
        var blockCount: Int

        var hasMultipleBlocks: Bool { blockCount > 1 }
    }

    /// Interprets raw clipboard text into the code + language the capture path
    /// should use, applying this hint precedence:
    ///
    /// 1. A bare URL remains plain text.
    /// 2. A Markdown fence's explicit info-string language (```swift) or stripped body.
    /// 3. ANSI escape codes, when no fence already narrowed the content.
    /// 4. A file path / drop-metadata extension, when the whole text is one path.
    /// 5. Weighted content scoring (`detect`).
    ///
    /// When the text contains exactly one fenced block, only that block's code is
    /// returned (surrounding prose is dropped). When it contains several, the
    /// blocks are concatenated (so the editor receives everything) and
    /// `blockCount` reports the count so the caller can defer to the editor.
    /// Plain text with no fence is returned unchanged, preserving prior behavior.
    static func interpret(_ raw: String) -> Interpretation {
        // A bare http(s) URL is plain text, not source — return it before any fence,
        // path, or keyword hint runs so a trailing extension in the URL path
        // (`…/styles.css`, `…/v0.1.0`) is never mistaken for a source language.
        if isURL(raw) {
            return Interpretation(code: raw, language: .plaintext, blockCount: 0)
        }
        let blocks = MarkdownFence.codeBlocks(in: raw)

        if blocks.isEmpty {
            // Terminal output (ANSI escapes) renders through the ANSI path, not scoring.
            if ANSIParser.containsANSI(raw) {
                return Interpretation(code: raw, language: .terminal, blockCount: 0)
            }
            // No fence. A lone file path names its language by extension;
            // otherwise fall back to content scoring on the original text.
            if let hinted = language(forPath: raw) {
                return Interpretation(code: raw, language: hinted, blockCount: 0)
            }
            return Interpretation(code: raw, language: detect(raw), blockCount: 0)
        }

        if blocks.count == 1, let block = blocks.first {
            let language = block.declaredLanguage ?? detect(block.code)
            return Interpretation(code: block.code, language: language, blockCount: 1)
        }

        // Multiple blocks: keep all the code for the editor, and pick the language
        // from the first block that declares one, else score the combined text.
        let joined = blocks.map(\.code).joined(separator: "\n\n")
        let declared = blocks.compactMap(\.declaredLanguage).first
        let language = declared ?? detect(joined)
        return Interpretation(code: joined, language: language, blockCount: blocks.count)
    }
}

/// Parser for GitHub-flavored Markdown fenced code blocks.
///
/// Recognizes both backtick (```) and tilde (~~~) fences, requires the closing
/// fence to use the same character and be at least as long as the opening one,
/// and reads the opening fence's info string for an explicit language. Kept a
/// separate namespace so the line scanning is straightforward to unit-test.
enum MarkdownFence {
    /// One fenced code block: its inner text (delimiters stripped, no trailing
    /// newline) and the language declared by its info string, if any.
    struct Block: Equatable {
        var code: String
        var declaredLanguage: Language?
    }

    /// Extracts every fenced code block in `text`, in document order. Returns an
    /// empty array when the text has no complete fence, so callers can treat
    /// "not fenced" and "no code" the same way.
    static func codeBlocks(in text: String) -> [Block] {
        // Split on any newline flavor (LF, CRLF, and bare CR — each is one
        // grapheme to `isNewline`) but keep empty lines so blank lines inside a
        // fence are preserved verbatim. This normalizes Windows clipboards.
        let lines =
            text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)

        var blocks: [Block] = []
        var index = 0
        while index < lines.count {
            guard let opening = fenceMarker(lines[index]) else {
                index += 1
                continue
            }
            // The info string is everything after the run of fence characters on
            // the opening line; its first whitespace-delimited token names the
            // language (CommonMark: the rest is ignored). Drop the same leading
            // spaces `fenceMarker` tolerates before the run, so an indented fence
            // (up to three spaces) still exposes its info string.
            let afterIndent = lines[index].drop { $0 == " " }
            let info = String(afterIndent.drop { $0 == opening.character })
                .trimmingCharacters(in: .whitespaces)
            let token = info.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            let declared =
                token.isEmpty
                ? nil
                : Language(rawValue: token.lowercased())
                    ?? LanguageDetector.language(forFileExtension: token)

            // Collect body lines until a matching closing fence (same character,
            // length ≥ opening) or end of input.
            var body: [String] = []
            var cursor = index + 1
            var closed = false
            while cursor < lines.count {
                if isClosingFence(lines[cursor], opening: opening) {
                    closed = true
                    break
                }
                body.append(lines[cursor])
                cursor += 1
            }

            // Only accept a properly closed fence; an unterminated fence is not a
            // code block (the text is treated as prose by the caller).
            if closed {
                blocks.append(
                    Block(code: body.joined(separator: "\n"), declaredLanguage: declared))
                index = cursor + 1
            } else {
                index += 1
            }
        }
        return blocks
    }

    /// If `line` begins a fence (after up to three leading spaces, per CommonMark),
    /// returns the fence character and its run length; otherwise `nil`.
    private static func fenceMarker(_ line: String) -> (character: Character, length: Int)? {
        let stripped = line.drop { $0 == " " }
        // More than three leading spaces would be an indented code block, not a
        // fence.
        guard line.count - stripped.count <= 3, let first = stripped.first,
            first == "`" || first == "~"
        else { return nil }
        let run = stripped.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        return (first, run)
    }

    /// Whether `line` is a valid closing fence for an open fence: the same fence
    /// character, a run at least as long as the opening one, and nothing but
    /// whitespace after the run (CommonMark forbids an info string on a close).
    private static func isClosingFence(
        _ line: String, opening: (character: Character, length: Int)
    ) -> Bool {
        guard let marker = fenceMarker(line),
            marker.character == opening.character,
            marker.length >= opening.length
        else { return false }
        let rest = line.drop { $0 == " " }.drop { $0 == marker.character }
        return rest.allSatisfy(\.isWhitespace)
    }
}
