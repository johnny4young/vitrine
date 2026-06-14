import AppIntents

/// App Intents picker enums for the automation surfaces (CS-034).
///
/// Each `AppEnum` exposes one of the app's existing model catalogs to Shortcuts and
/// the Intents UI as a friendly, localized picker. The cases are kept deliberately
/// thin wrappers that map back to the real model type (`Language`, a `Theme` id, an
/// `ExportPreset` id, and `ExportFormat`), so there is a single source of truth for
/// what the app can render and the intent parameters cannot drift from it. The color
/// profile is intentionally not exposed — automation always outputs deliberate sRGB
/// (the universally safe space, CS-024); the advanced P3 option stays an in-app choice.
///
/// `caseDisplayRepresentations` uses the same display names the in-app pickers use,
/// so a Shortcut shows "X / Twitter", "Dracula", "Swift", etc. — not raw ids.

// MARK: - Language

/// The language an automation renders with, mirroring `Language` (CS-034).
///
/// "Automatic" is the default and most useful case: it defers to Vitrine's own
/// detection (Markdown fences, file-path hints, then content scoring), so a Shortcut
/// that just passes a snippet still gets correct highlighting without the user
/// picking a language. Every advertised `Language` is offered explicitly too.
enum SnapshotLanguageAppEnum: String, AppEnum, CaseIterable {
    case automatic
    case swift, python, javascript, typescript, go, rust, ruby, java, kotlin
    case c, cpp, csharp, objectivec, scala, dart, elixir, haskell, lua, r, perl
    case php, html, css, scss, json, yaml, toml, bash, sql, graphql, dockerfile
    case diff, markdown
    case plaintext

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Language")

    // App Intents metadata is `nonisolated` static data, so the picker titles are
    // literals here rather than reads of the main-actor `Language.displayName`. A
    // coverage test asserts each non-automatic case still maps to a real `Language`
    // and that these titles match the in-app display names, so they cannot drift.
    static var caseDisplayRepresentations: [SnapshotLanguageAppEnum: DisplayRepresentation] {
        [
            .automatic: "Automatic (detect)",
            .swift: "Swift",
            .python: "Python",
            .javascript: "JavaScript",
            .typescript: "TypeScript",
            .go: "Go",
            .rust: "Rust",
            .ruby: "Ruby",
            .java: "Java",
            .kotlin: "Kotlin",
            .c: "C",
            .cpp: "C++",
            .csharp: "C#",
            .objectivec: "Objective-C",
            .scala: "Scala",
            .dart: "Dart",
            .elixir: "Elixir",
            .haskell: "Haskell",
            .lua: "Lua",
            .r: "R",
            .perl: "Perl",
            .php: "PHP",
            .html: "HTML",
            .css: "CSS",
            .scss: "SCSS",
            .json: "JSON",
            .yaml: "YAML",
            .toml: "TOML",
            .bash: "Shell",
            .sql: "SQL",
            .graphql: "GraphQL",
            .dockerfile: "Dockerfile",
            .diff: "Diff",
            .markdown: "Markdown",
            .plaintext: "Plain Text",
        ]
    }

    /// The model `Language` this case selects, or `nil` for `.automatic` (which
    /// means "let Vitrine detect the language").
    var language: Language? {
        self == .automatic ? nil : Language(rawValue: rawValue)
    }
}

// MARK: - Theme

/// A built-in syntax theme an automation can pick, mirroring `Theme.builtIns`
/// (CS-034).
///
/// "Default" keeps the user's current theme; every other case is a built-in theme by
/// its stable id. Only built-ins are offered because a user's custom themes (CS-031)
/// are machine-local and not addressable by a stable, shareable id in a Shortcut.
enum SnapshotThemeAppEnum: String, AppEnum, CaseIterable {
    case `default`
    case oneDark = "one-dark"
    case nightOwl = "night-owl"
    case dracula
    case monokai
    case nord
    case gruvbox
    case tokyoNight = "tokyo-night"
    case solarized
    case githubDark = "github-dark"
    case xcodeDark = "xcode-dark"
    case github
    case oneLight = "one-light"
    case solarizedLight = "solarized-light"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Theme")

    // Literal picker titles (App Intents metadata is `nonisolated`). A coverage test
    // asserts each non-default case's raw value resolves to a real built-in theme and
    // that these titles match the catalog display names, so they cannot drift.
    static var caseDisplayRepresentations: [SnapshotThemeAppEnum: DisplayRepresentation] {
        [
            .default: "Default (current theme)",
            .oneDark: "One Dark",
            .nightOwl: "Night Owl",
            .dracula: "Dracula",
            .monokai: "Monokai",
            .nord: "Nord",
            .gruvbox: "Gruvbox",
            .tokyoNight: "Tokyo Night",
            .solarized: "Solarized",
            .githubDark: "GitHub Dark",
            .xcodeDark: "Xcode Dark",
            .github: "GitHub",
            .oneLight: "One Light",
            .solarizedLight: "Solarized Light",
        ]
    }

    /// The built-in theme id this case selects, or `nil` for `.default` (keep the
    /// current theme).
    var themeID: String? { self == .default ? nil : rawValue }
}

// MARK: - Destination preset

/// A destination preset an automation can apply, mirroring `ExportPreset.all`
/// (CS-034). "None" applies no preset (the user's own framing); every other case is
/// a preset by its stable id.
enum SnapshotPresetAppEnum: String, AppEnum, CaseIterable {
    case none
    case twitter
    case linkedin
    case keynote
    case docs
    case transparentSlide = "transparent-slide"
    case openGraph = "opengraph"
    case instagramStory = "instagram-story"
    case githubBanner = "github-banner"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Destination Preset")

    // Literal picker titles (App Intents metadata is `nonisolated`). A coverage test
    // asserts each non-none case's raw value resolves to a real `ExportPreset` and
    // that these titles match the catalog display names, so they cannot drift.
    static var caseDisplayRepresentations: [SnapshotPresetAppEnum: DisplayRepresentation] {
        [
            .none: "None",
            .twitter: "X / Twitter",
            .linkedin: "LinkedIn",
            .keynote: "Keynote",
            .docs: "Docs / Blog",
            .transparentSlide: "Transparent Slide",
            .openGraph: "OpenGraph 1200×630",
            .instagramStory: "Instagram Story",
            .githubBanner: "GitHub Banner",
        ]
    }

    /// The preset id this case selects, or `nil` for `.none`.
    var presetID: String? { self == .none ? nil : rawValue }
}

// MARK: - Output format

/// The image format an automation produces, mirroring `ExportFormat` (CS-034).
enum SnapshotFormatAppEnum: String, AppEnum, CaseIterable {
    case png
    case pdf

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Image Format")

    static var caseDisplayRepresentations: [SnapshotFormatAppEnum: DisplayRepresentation] {
        [
            .png: "PNG",
            .pdf: "PDF",
        ]
    }

    /// The model `ExportFormat` this case maps to.
    var format: ExportFormat { ExportFormat(rawValue: rawValue) ?? .png }
}
