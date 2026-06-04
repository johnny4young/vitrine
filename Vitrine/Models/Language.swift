import Foundation

/// A programming language Vitrine can highlight. `hljsName` maps to the
/// Highlight.js identifier used by Highlightr (CS-004/052).
///
/// ## Adding a language (a one-file change, CS-052)
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
}
