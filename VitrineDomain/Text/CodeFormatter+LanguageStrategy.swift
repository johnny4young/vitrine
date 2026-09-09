extension Language {
    /// How ``CodeFormatter/tidy(_:language:)`` should tidy this language, picked so each
    /// gets the safe transform. Brace/tag languages re-indent from nesting;
    /// JSON gets its exact re-indent; whitespace/keyword-significant languages are only
    /// dedented (re-indenting them from brackets would corrupt the block structure); and
    /// formats where leading whitespace is data are left untouched.
    enum FormatStrategy {
        case json
        case markup
        case sql
        case reindentBraces
        case reindentTags
        case dedentOnly
        case leaveAlone
    }

    nonisolated var formatStrategy: FormatStrategy {
        switch self {
        case .json: .json
        case .html: .markup
        case .sql: .sql
        case .javascript, .typescript: .reindentTags
        case .swift, .go, .rust, .java, .kotlin, .c, .cpp, .csharp, .objectivec,
            .scala, .dart, .css, .scss, .php, .r, .perl, .graphql:
            .reindentBraces
        case .python, .yaml, .ruby, .haskell, .lua, .elixir, .bash, .toml,
            .dockerfile:
            .dedentOnly
        case .diff, .markdown, .terminal, .plaintext: .leaveAlone
        }
    }

    /// The indentation unit re-indenting emits: a tab for Go (gofmt's convention), two
    /// spaces otherwise (the web/JS norm and a safe neutral default for the rest).
    nonisolated var indentUnit: String {
        switch self {
        case .go: "\t"
        default: "  "
        }
    }
}
