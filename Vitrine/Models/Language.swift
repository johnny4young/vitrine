import Foundation

/// A programming language Vitrine can highlight. `hljsName` maps to the
/// Highlight.js identifier used by Highlightr (CS-004).
enum Language: String, CaseIterable, Identifiable {
    case swift, python, javascript, typescript, go, rust, ruby, java, kotlin
    case c, cpp, csharp, php, html, css, json, yaml, bash, sql, markdown
    case plaintext

    var id: String { rawValue }

    /// Name shown in the language picker.
    var displayName: String {
        switch self {
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .go: "Go"
        case .rust: "Rust"
        case .ruby: "Ruby"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .c: "C"
        case .cpp: "C++"
        case .csharp: "C#"
        case .php: "PHP"
        case .html: "HTML"
        case .css: "CSS"
        case .json: "JSON"
        case .yaml: "YAML"
        case .bash: "Shell"
        case .sql: "SQL"
        case .markdown: "Markdown"
        case .plaintext: "Plain Text"
        }
    }

    /// Highlight.js language identifier passed to Highlightr.
    var hljsName: String {
        switch self {
        case .cpp: "cpp"
        case .csharp: "csharp"
        case .bash: "bash"
        case .plaintext: "plaintext"
        default: rawValue
        }
    }
}
