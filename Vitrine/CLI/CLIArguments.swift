import Foundation

/// A problem the CLI reports to the user, mapped to a clear message and a process
/// exit code (CS-033). Every failure mode the `render` command can hit has a case
/// here so the executable never prints a raw Swift error or crashes.
///
/// `nonisolated` so it is a plain `Sendable & Equatable` error: the executable throws
/// and catches it across isolation boundaries, and the test suite can assert on it
/// with Swift Testing's `#expect(throws:)` (which requires a `Sendable` error). Its
/// `message` composes the equally `nonisolated` `CLIUsage.text`.
nonisolated enum CLIError: Error, Equatable {
    /// `--help`/`-h` was requested: not an error, but it short-circuits parsing so
    /// the caller prints usage and exits successfully.
    case helpRequested
    /// No subcommand, or an unrecognized one, was given.
    case unknownCommand(String)
    /// A flag the parser does not recognize.
    case unknownFlag(String)
    /// A flag that needs a value was the last token (its value is missing).
    case missingValue(flag: String)
    /// A required positional/option was not supplied (e.g. the input file or `--out`).
    case missingRequired(String)
    /// A value was supplied but is not valid for its flag (bad number, unknown id…).
    case invalidValue(flag: String, value: String)
    /// Two otherwise-valid options were combined in a way that would be ambiguous.
    case incompatibleOptions(String)
    /// The input source file could not be read.
    case inputUnreadable(path: String)
    /// The input file decoded but is not text (likely a binary file).
    case inputNotText(path: String)
    /// Rendering produced no image (an internal renderer failure).
    case renderFailed
    /// Encoding or writing the output file failed.
    case writeFailed(path: String)
    /// `--edit` could not open Vitrine to receive the handoff (no app registered for the
    /// `vitrine://` scheme, or a Launch Services failure). Surfaced so a script sees a
    /// non-zero exit instead of a false success.
    case editorOpenFailed
    /// The PRO tier is required for command-line/automation rendering but is not
    /// active (CS-094). Reported before any file work so a free build never renders.
    case proRequired

    /// A short, human-readable explanation suitable for stderr.
    var message: String {
        switch self {
        case .helpRequested:
            CLIUsage.text
        case .unknownCommand(let command):
            "Unknown command \"\(command)\". The commands are \"render\" and \"batch\"."
        case .unknownFlag(let flag):
            "Unknown option \"\(flag)\"."
        case .missingValue(let flag):
            "Option \"\(flag)\" needs a value."
        case .missingRequired(let what):
            "Missing required \(what)."
        case .invalidValue(let flag, let value):
            "\"\(value)\" is not a valid value for \"\(flag)\"."
        case .incompatibleOptions(let message):
            message
        case .inputUnreadable(let path):
            "Could not read the input file at \"\(path)\"."
        case .inputNotText(let path):
            "The input file at \"\(path)\" is not text."
        case .renderFailed:
            "Rendering failed to produce an image."
        case .writeFailed(let path):
            "Could not write the output to \"\(path)\"."
        case .editorOpenFailed:
            "Could not open Vitrine to receive the output. Is Vitrine installed?"
        case .proRequired:
            "Vitrine PRO is required for command-line and automation rendering. "
                + "Activate PRO in the Vitrine app to unlock it."
        }
    }

    /// The process exit code this failure maps to. `0` is reserved for success and
    /// for the help request (which is not a failure); every genuine error is `1`.
    var exitCode: Int32 {
        switch self {
        case .helpRequested: 0
        default: 1
        }
    }
}

/// Parses `vitrine` command-line arguments into a `CLIOptions` (CS-033).
///
/// The grammar is deliberately tiny and dependency-free (no third-party arg parser):
/// a single `render` subcommand, one positional input path, a required `--out`, and
/// a handful of `--flag value` options plus the boolean `--transparent`. Keeping it
/// hand-rolled means the CLI adds no new package to the app and the parser is a pure,
/// synchronous function that is trivial to unit-test.
///
/// Unknown flags, missing values, and bad enum/number values all throw a specific
/// `CLIError` so a docs/automation pipeline fails loudly with a clear message instead
/// of silently rendering the wrong thing.
///
/// Main-actor isolated (the module default) so it can read the main-actor model
/// catalogs (`ExportPreset`, `SettingsDefaults`) while validating ids and ranges. The
/// executable runs it from `main.swift`, whose top-level code is on the main actor.
@MainActor
enum CLIArguments {
    /// Parses the argument list *after* the executable name (i.e. `CommandLine
    /// .arguments.dropFirst()`), returning the options for a `render` command.
    ///
    /// Throws `CLIError.helpRequested` for `--help`/`-h` (the caller prints usage),
    /// and a specific error for any malformed input.
    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var remaining = ArraySlice(arguments)

        // A bare invocation, or a top-level help request, shows usage.
        guard let command = remaining.first else { throw CLIError.helpRequested }
        if command == "--help" || command == "-h" { throw CLIError.helpRequested }
        let mode: CLIOptions.Command
        switch command {
        case "render": mode = .render
        case "batch": mode = .batch
        default: throw CLIError.unknownCommand(command)
        }
        remaining = remaining.dropFirst()

        var inputPath: String?
        var outputPath: String?
        var themeID: String?
        var languageID: String?
        var presetID: String?
        var scale: Int?
        var terminalColumns: Int?
        var wrapColumns: Int?
        var format: ExportFormat = .png
        var profile: ColorProfile = .fallback
        var transparent = false
        var windowTitle: String?
        var metadataFilename: String?
        var metadataTitle: String?
        var metadataCaption: String?
        var showLanguageBadge = false
        var readStdin = false
        var copyToClipboard = false
        var openInEditor = false
        var textSidecar = false
        var markdownSidecar = false

        /// Pops the value that must follow a `--flag`, or throws if it is absent.
        func value(for flag: String) throws -> String {
            guard let next = remaining.first else { throw CLIError.missingValue(flag: flag) }
            remaining = remaining.dropFirst()
            return next
        }

        while let token = remaining.first {
            remaining = remaining.dropFirst()
            switch token {
            case "--help", "-h":
                throw CLIError.helpRequested
            case "--out", "-o":
                outputPath = try value(for: token)
            case "--theme":
                themeID = try resolveTheme(try value(for: token))
            case "--language", "--lang":
                languageID = try resolveLanguage(try value(for: token))
            case "--preset":
                presetID = try resolvePreset(try value(for: token))
            case "--scale":
                scale = try resolveScale(try value(for: token), flag: token)
            case "--terminal-width":
                terminalColumns = try resolveColumns(try value(for: token), flag: token)
            case "--wrap-columns", "--wrap":
                wrapColumns = try resolveWrapColumns(try value(for: token), flag: token)
            case "--format":
                format = try resolveFormat(try value(for: token))
            case "--profile":
                profile = try resolveProfile(try value(for: token))
            case "--transparent":
                transparent = true
            case "--window-title":
                windowTitle = try value(for: token)
            case "--filename":
                metadataFilename = try value(for: token)
            case "--title":
                metadataTitle = try value(for: token)
            case "--caption":
                metadataCaption = try value(for: token)
            case "--language-badge", "--show-language-badge":
                showLanguageBadge = true
            case "--stdin":
                readStdin = true
            case "--copy":
                copyToClipboard = true
            case "--edit", "-e":
                openInEditor = true
            case "--text-sidecar":
                textSidecar = true
            case "--markdown-sidecar":
                markdownSidecar = true
            default:
                if token.hasPrefix("-") {
                    throw CLIError.unknownFlag(token)
                }
                // The first non-flag token is the input path; a second positional is
                // unexpected and rejected so a stray argument is not silently ignored.
                guard inputPath == nil else { throw CLIError.unknownFlag(token) }
                inputPath = token
            }
        }

        // `--stdin`, `--copy`, and `--edit` are render-only (a batch needs real folders).
        if mode == .batch, readStdin || copyToClipboard || openInEditor {
            let flag = readStdin ? "--stdin" : (copyToClipboard ? "--copy" : "--edit")
            throw CLIError.unknownFlag(flag)
        }
        if readStdin, let inputPath {
            throw CLIError.incompatibleOptions(
                "Cannot combine --stdin with input file \"\(inputPath)\".")
        }
        let metadataHeaderRequested =
            windowTitle != nil || metadataFilename != nil
            || metadataTitle != nil || metadataCaption != nil || showLanguageBadge

        // `--edit` hands the source to the running editor instead of rendering, so it
        // produces no image: pairing it with `--copy` or `--out` would be ambiguous.
        if openInEditor {
            if copyToClipboard {
                throw CLIError.incompatibleOptions("Cannot combine --edit with --copy.")
            }
            if outputPath != nil {
                throw CLIError.incompatibleOptions("Cannot combine --edit with --out.")
            }
            if textSidecar {
                throw CLIError.incompatibleOptions("Cannot combine --edit with --text-sidecar.")
            }
            if markdownSidecar {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with --markdown-sidecar.")
            }
            if metadataHeaderRequested {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with metadata header options.")
            }
            if wrapColumns != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with --wrap-columns.")
            }
        }
        // A sidecar sits next to a written image, so it needs an `--out` path —
        // a clipboard-only copy (`--copy` with no `--out`) has no file to accompany.
        if textSidecar, outputPath == nil {
            throw CLIError.incompatibleOptions(
                "--text-sidecar needs an --out path to write beside.")
        }
        if markdownSidecar, outputPath == nil {
            throw CLIError.incompatibleOptions(
                "--markdown-sidecar needs an --out path to write beside.")
        }
        // Input is a file unless reading stdin; output is required unless copying the
        // image to the clipboard or handing it to the editor (`--edit`), neither of
        // which writes a file.
        let resolvedInput: String
        if readStdin {
            resolvedInput = ""
        } else {
            guard let inputPath else {
                throw CLIError.missingRequired(mode == .batch ? "input folder" : "input file")
            }
            resolvedInput = inputPath
        }
        let resolvedOutput: String
        if copyToClipboard || openInEditor {
            resolvedOutput = outputPath ?? ""
        } else {
            guard let outputPath else {
                throw CLIError.missingRequired(
                    mode == .batch ? "--out output folder" : "--out output path")
            }
            resolvedOutput = outputPath
        }

        return CLIOptions(
            command: mode,
            inputPath: resolvedInput,
            outputPath: resolvedOutput,
            themeID: themeID,
            language: languageID.flatMap(Language.init(rawValue:)),
            presetID: presetID,
            scale: scale,
            terminalColumns: terminalColumns,
            wrapColumns: wrapColumns,
            format: format,
            profile: profile,
            transparent: transparent,
            windowTitle: windowTitle,
            metadataFilename: metadataFilename,
            metadataTitle: metadataTitle,
            metadataCaption: metadataCaption,
            showLanguageBadge: showLanguageBadge,
            readStdin: readStdin,
            copyToClipboard: copyToClipboard,
            openInEditor: openInEditor,
            textSidecar: textSidecar,
            markdownSidecar: markdownSidecar
        )
    }

    // MARK: - Value resolution (each rejects an unknown id with a clear error)

    /// Validates a theme id against the built-in catalog so a typo fails up front
    /// rather than silently falling back to One Dark at render time.
    private static func resolveTheme(_ raw: String) throws -> String {
        guard Theme.builtInIDs.contains(raw) else {
            throw CLIError.invalidValue(flag: "--theme", value: raw)
        }
        return raw
    }

    /// Validates a language id against the advertised catalog.
    private static func resolveLanguage(_ raw: String) throws -> String {
        guard Language(rawValue: raw) != nil else {
            throw CLIError.invalidValue(flag: "--language", value: raw)
        }
        return raw
    }

    /// Validates a destination-preset id against the catalog.
    private static func resolvePreset(_ raw: String) throws -> String {
        guard ExportPreset.preset(withID: raw) != nil else {
            throw CLIError.invalidValue(flag: "--preset", value: raw)
        }
        return raw
    }

    /// Parses and range-checks the export scale (1...3).
    private static func resolveScale(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw),
            SettingsDefaults.exportScaleRange.contains(value)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks an explicit terminal capture width (1...1000, the bound
    /// the grid emulator clamps to). Pins the reconstruction width for `--language
    /// terminal` output instead of inferring it; ignored for non-terminal languages.
    private static func resolveColumns(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw), (1...1000).contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the editor's code soft-wrap width. Uses the same
    /// bounds as the Style pane, so a CLI render and a saved editor config agree.
    private static func resolveWrapColumns(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw), SettingsDefaults.wrapColumnsRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses the output format (`png`/`pdf`/`heic`).
    private static func resolveFormat(_ raw: String) throws -> ExportFormat {
        guard let format = ExportFormat(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--format", value: raw)
        }
        return format
    }

    /// Parses the color profile, accepting the documented spellings `srgb` and `p3`
    /// in addition to the raw enum names.
    private static func resolveProfile(_ raw: String) throws -> ColorProfile {
        switch raw.lowercased() {
        case "srgb", "srgb-iec61966-2.1": return .sRGB
        case "p3", "displayp3", "display-p3": return .displayP3
        default: throw CLIError.invalidValue(flag: "--profile", value: raw)
        }
    }
}

/// The `vitrine render` usage text, shown for `--help` and on a usage error.
///
/// `nonisolated` (a pure static string) so `CLIError.message` — itself nonisolated —
/// can compose it, and so the executable and tests can read it from any context.
nonisolated enum CLIUsage {
    static let text = """
        vitrine — render code to an image from the command line.

        USAGE:
          vitrine render <input-file> --out <image> [options]
          vitrine render --stdin --copy [options]
          vitrine render (<input-file> | --stdin) --edit [options]
          vitrine batch <input-folder> --out <output-folder> [options]
          vitrine shell-init [zsh|bash|fish]   Print the terminal-capture shell helpers.

        OPTIONS:
          -o, --out <path>       Output image path (required unless --copy / --edit).
          --copy                 Copy the rendered image to the clipboard.
          -e, --edit             Open the source in Vitrine's editor instead of
                                 rendering (no image is written; not with --copy/--out).
          --stdin                Read the source from standard input (e.g. a pipe).
          --theme <id>           Syntax theme id (e.g. one-dark, dracula, nord).
          --language <id>        Language id (e.g. swift, python, terminal). Inferred
                                 when omitted.
          --preset <id>          Destination preset (twitter, linkedin, keynote,
                                 docs, transparent-slide, opengraph).
          --scale <1|2|3>        Export resolution multiplier. Defaults to the app
                                 default, or the preset's recommended scale.
          --terminal-width <n>   Reconstruct terminal output at exactly n columns
                                 instead of inferring the width (1-1000). Only
                                 affects --language terminal; set by `vgrab -w`.
          --wrap-columns <n>     Soft-wrap long code lines at n columns (40-200).
          --format <png|pdf|heic>  Output format. Defaults to png; pdf is the vector
                                 option, heic the compact raster one.
          --profile <srgb|p3>    PNG color profile. Defaults to srgb.
          --transparent          Render a real transparent background.
          --window-title <text>  Title shown in the rendered window chrome.
          --filename <text>      Filename chip shown in the metadata header.
          --title <text>         Title shown in the metadata header.
          --caption <text>       Caption shown below the metadata title.
          --language-badge       Show the language badge in the metadata header.
          --text-sidecar         Also write a .txt next to --out with the source as
                                 selectable text (terminal escapes stripped).
          --markdown-sidecar     Also write a .md next to --out: the image reference
                                 plus the source in a fenced code block, ready to
                                 paste into a README or post.
          -h, --help             Show this help.

        Code rendering is fully local: it never needs the network, screen recording,
        or Accessibility permissions.
        """
}
