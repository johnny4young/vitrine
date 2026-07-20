import Foundation

/// A programming language Vitrine can highlight. `hljsName` maps to the
/// Highlight.js identifier used by Highlightr.
///
/// ## Adding a language (a one-file change)
///
/// To advertise a new language, add a `case` here, then extend `displayName`
/// (the picker label) and — only if the raw value differs from the Highlight.js
/// identifier — `hljsName`. The Highlight.js id (or one of its aliases) must
/// resolve in the bundled engine; `CoverageMatrixTests` enforces that every
/// advertised language highlights without falling back to plain text, so a typo
/// or an unsupported id fails the build rather than shipping a dead entry.
enum Language: String, CaseIterable, Identifiable {
    case swift, python, javascript, typescript, go, rust, ruby, java, kotlin
    case c, cpp, csharp, objectivec, scala, dart, elixir, haskell, lua, r, perl
    case php, html, css, scss, json, yaml, toml, bash, sql, graphql, dockerfile
    case diff, markdown
    /// Terminal / shell output with ANSI escape codes. Not a Highlight.js language —
    /// it is colored by its own escape sequences through the ANSI render path, so it
    /// is excluded from the Highlightr coverage checks.
    case terminal
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
        case .objectivec: "Objective-C"
        case .scala: "Scala"
        case .dart: "Dart"
        case .elixir: "Elixir"
        case .haskell: "Haskell"
        case .lua: "Lua"
        case .r: "R"
        case .perl: "Perl"
        case .php: "PHP"
        case .html: "HTML"
        case .css: "CSS"
        case .scss: "SCSS"
        case .json: "JSON"
        case .yaml: "YAML"
        case .toml: "TOML"
        case .bash: "Shell"
        case .sql: "SQL"
        case .graphql: "GraphQL"
        case .dockerfile: "Dockerfile"
        case .diff: "Diff"
        case .markdown: "Markdown"
        case .terminal: "Terminal"
        case .plaintext: "Plain Text"
        }
    }

    /// Highlight.js language identifier (or alias) passed to Highlightr.
    ///
    /// Most cases match their raw value, so they are covered by `default`. The
    /// switch lists only the languages whose Highlight.js id differs from the
    /// Swift case name — including a few that resolve through an alias (HTML →
    /// `xml`, TOML → `ini`).
    var hljsName: String {
        switch self {
        case .cpp: "cpp"
        case .csharp: "csharp"
        case .objectivec: "objectivec"
        case .html: "xml"
        case .toml: "ini"
        case .bash: "bash"
        case .plaintext: "plaintext"
        default: rawValue
        }
    }

    /// The canonical filename extension for this language, lowercased and without
    /// the leading dot (e.g. Swift → `swift`, Python → `py`), or `nil` for
    /// `plaintext`, which has no single source-file extension.
    ///
    /// This is the *forward* mapping (one language → one extension). The
    /// *reverse* mapping (extension → language) lives in `LanguageDetector`,
    /// which also recognizes common aliases (`.yml`, `.htm`, `.cc`, `.h`, …) that
    /// cannot round-trip back to a single canonical extension.
    var fileExtension: String? {
        switch self {
        case .swift: "swift"
        case .python: "py"
        case .javascript: "js"
        case .typescript: "ts"
        case .go: "go"
        case .rust: "rs"
        case .ruby: "rb"
        case .java: "java"
        case .kotlin: "kt"
        case .c: "c"
        case .cpp: "cpp"
        case .csharp: "cs"
        case .objectivec: "m"
        case .scala: "scala"
        case .dart: "dart"
        case .elixir: "ex"
        case .haskell: "hs"
        case .lua: "lua"
        case .r: "r"
        case .perl: "pl"
        case .php: "php"
        case .html: "html"
        case .css: "css"
        case .scss: "scss"
        case .json: "json"
        case .yaml: "yaml"
        case .toml: "toml"
        case .bash: "sh"
        case .sql: "sql"
        case .graphql: "graphql"
        case .dockerfile: "dockerfile"
        case .diff: "diff"
        case .markdown: "md"
        case .terminal: nil
        case .plaintext: nil
        }
    }
}
