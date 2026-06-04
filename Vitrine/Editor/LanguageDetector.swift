import Foundation

/// Best-effort content/language detection from clipboard text (CS-004).
/// v0.1 ships a light heuristic; a more robust detector is future work.
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

    /// Small keyword heuristic. Returns `.plaintext` when unsure.
    static func detect(_ code: String) -> Language {
        let lower = code.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { lower.contains($0) } }

        if has("import swiftui", "func ", "guard let", "@state") && lower.contains("func ") {
            return .swift
        }
        if has("def ", "elif ", "print(") && lower.contains("def ") { return .python }
        if has("package main", "func main(", "fmt.") { return .go }
        if has("function ", "const ", "=>", "console.log") {
            return lower.contains(": ") ? .typescript : .javascript
        }
        if has("select ", "insert into", "update ", " where ") { return .sql }
        if has("<html", "<div", "</") { return .html }
        if has("#!/bin/", "echo ") { return .bash }
        return .plaintext
    }
}
