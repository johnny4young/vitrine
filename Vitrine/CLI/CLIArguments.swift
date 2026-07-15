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
    /// An output path already exists and `--no-overwrite` requested a safe run.
    case outputExists(path: String)
    /// Encoding or writing the output file failed.
    case writeFailed(path: String)
    /// A batch found no renderable inputs and `--fail-on-empty` requested a failing exit.
    case batchEmpty(skipped: Int)
    /// A batch completed at least some work, but `--fail-on-skipped` requested a
    /// failing exit when unreadable/non-text files were skipped.
    case batchSkipped(rendered: Int, skipped: Int)
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
            "Unknown command \"\(command)\". The commands are \"render\", \"batch\", \"list\", \"shell-init\", and \"version\"."
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
        case .outputExists(let path):
            "The output already exists at \"\(path)\". Remove it or omit --no-overwrite."
        case .writeFailed(let path):
            "Could not write the output to \"\(path)\"."
        case .batchEmpty(let skipped):
            "Batch found no renderable input files"
                + (skipped > 0 ? " (skipped \(skipped) file\(skipped == 1 ? "" : "s"))" : "")
                + "."
        case .batchSkipped(let rendered, let skipped):
            "Batch rendered \(rendered) image\(rendered == 1 ? "" : "s") but skipped "
                + "\(skipped) file\(skipped == 1 ? "" : "s")."
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
/// a `render` or `batch` subcommand, one positional input path/folder, a command-specific
/// `--out` requirement, and a small set of boolean / `--flag value` options. Pure
/// metadata commands such as `list` and `shell-init` are handled before this parser so
/// they can run without AppKit or the PRO render gate. Keeping the parser hand-rolled
/// means the CLI adds no new package to the app and remains straightforward to unit-test.
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
        var quiet = false
        var jsonOutput = false
        var themeID: String?
        var languageID: String?
        var presetID: String?
        var scale: Int?
        var fontName: String?
        var fontLigatures: Bool?
        var fontSize: Double?
        var padding: Double?
        var cornerRadius: Double?
        var shadowRadius: Double?
        var terminalColumns: Int?
        var wrapColumns: Int?
        var formatCode = false
        var explicitFormat: ExportFormat?
        var profile: ColorProfile = .fallback
        var transparent = false
        var background: BackgroundStyle?
        var gradientBackgroundRequested = false
        var solidBackgroundRequested = false
        var noOverwrite = false
        var windowTitle: String?
        var metadataFilename: String?
        var stdinFilename: String?
        var metadataTitle: String?
        var metadataCaption: String?
        var showLanguageBadge = false
        var showLineNumbers: Bool?
        var showChrome: Bool?
        var showShadow: Bool?
        var highlightedLineRanges: [ClosedRange<Int>]?
        var redactedLineRanges: [ClosedRange<Int>]?
        var redactSecrets = false
        var focusHighlightedLines: Bool?
        var diffDecorations: Bool?
        var recursiveBatch = false
        var failOnSkipped = false
        var failOnEmpty = false
        var skippedReportPath: String?
        var batchManifestPath: String?
        var dryRunBatch = false
        var batchIncludeExtensions: Set<String> = []
        var batchExcludeExtensions: Set<String> = []
        var readStdin = false
        var copyToClipboard = false
        var openInEditor = false
        var textSidecar = false
        var markdownSidecar = false
        var htmlSidecar = false

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
            case "--quiet", "-q":
                quiet = true
            case "--json":
                jsonOutput = true
            case "--theme":
                themeID = try resolveTheme(try value(for: token))
            case "--language", "--lang":
                languageID = try resolveLanguage(try value(for: token))
            case "--preset":
                presetID = try resolvePreset(try value(for: token))
            case "--scale":
                scale = try resolveScale(try value(for: token), flag: token)
            case "--font":
                fontName = try resolveFont(try value(for: token))
            case "--font-ligatures":
                fontLigatures = true
            case "--no-font-ligatures":
                fontLigatures = false
            case "--font-size":
                fontSize = try resolveFontSize(try value(for: token), flag: token)
            case "--padding":
                padding = try resolvePadding(try value(for: token), flag: token)
            case "--corner-radius":
                cornerRadius = try resolveCornerRadius(try value(for: token), flag: token)
            case "--shadow-radius":
                shadowRadius = try resolveShadowRadius(try value(for: token), flag: token)
            case "--terminal-width":
                terminalColumns = try resolveColumns(try value(for: token), flag: token)
            case "--wrap-columns", "--wrap":
                wrapColumns = try resolveWrapColumns(try value(for: token), flag: token)
            case "--format-code", "--tidy":
                formatCode = true
            case "--format":
                explicitFormat = try resolveFormat(try value(for: token))
            case "--profile":
                profile = try resolveProfile(try value(for: token))
            case "--transparent":
                transparent = true
            case "--background":
                background = .gradient(try resolveBackground(try value(for: token)))
                gradientBackgroundRequested = true
            case "--background-color":
                background = .solid(try resolveBackgroundColor(try value(for: token)))
                solidBackgroundRequested = true
            case "--no-overwrite", "--no-clobber":
                noOverwrite = true
            case "--window-title":
                windowTitle = try value(for: token)
            case "--filename":
                metadataFilename = try value(for: token)
            case "--stdin-name", "--stdin-filename":
                stdinFilename = try value(for: token)
            case "--title":
                metadataTitle = try value(for: token)
            case "--caption":
                metadataCaption = try value(for: token)
            case "--language-badge", "--show-language-badge":
                showLanguageBadge = true
            case "--line-numbers":
                showLineNumbers = true
            case "--no-line-numbers":
                showLineNumbers = false
            case "--chrome":
                showChrome = true
            case "--no-chrome":
                showChrome = false
            case "--shadow":
                showShadow = true
            case "--no-shadow":
                showShadow = false
            case "--highlight-lines":
                highlightedLineRanges = try resolveLineRanges(try value(for: token), flag: token)
            case "--redact-lines":
                redactedLineRanges = try resolveLineRanges(try value(for: token), flag: token)
            case "--redact-secrets":
                redactSecrets = true
            case "--focus-lines":
                focusHighlightedLines = true
            case "--no-focus-lines":
                focusHighlightedLines = false
            case "--diff-bands":
                diffDecorations = true
            case "--no-diff-bands":
                diffDecorations = false
            case "--recursive":
                recursiveBatch = true
            case "--fail-on-skipped":
                failOnSkipped = true
            case "--fail-on-empty":
                failOnEmpty = true
            case "--skipped-report":
                skippedReportPath = try value(for: token)
            case "--manifest":
                batchManifestPath = try value(for: token)
            case "--dry-run":
                dryRunBatch = true
            case "--include-ext":
                batchIncludeExtensions.formUnion(
                    try resolveExtensionList(try value(for: token), flag: token))
            case "--exclude-ext":
                batchExcludeExtensions.formUnion(
                    try resolveExtensionList(try value(for: token), flag: token))
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
            case "--html-sidecar":
                htmlSidecar = true
            case "--sidecars":
                let sidecars = try resolveSidecars(try value(for: token), flag: token)
                textSidecar = textSidecar || sidecars.text
                markdownSidecar = markdownSidecar || sidecars.markdown
                htmlSidecar = htmlSidecar || sidecars.html
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

        // `--stdin`, stdin filename hints, `--copy`, and `--edit` are render-only
        // (a batch needs real folders).
        if mode == .batch, readStdin || stdinFilename != nil || copyToClipboard || openInEditor {
            let flag =
                readStdin
                ? "--stdin"
                : (stdinFilename != nil ? "--stdin-name" : (copyToClipboard ? "--copy" : "--edit"))
            throw CLIError.unknownFlag(flag)
        }
        if stdinFilename != nil, !readStdin {
            throw CLIError.incompatibleOptions("--stdin-name requires --stdin.")
        }
        if quiet, jsonOutput {
            throw CLIError.incompatibleOptions("Cannot combine --quiet with --json.")
        }
        if gradientBackgroundRequested, solidBackgroundRequested {
            throw CLIError.incompatibleOptions(
                "Cannot combine --background with --background-color.")
        }
        if transparent, background != nil {
            throw CLIError.incompatibleOptions(
                "Cannot combine --transparent with --background or --background-color.")
        }
        if readStdin, let inputPath {
            throw CLIError.incompatibleOptions(
                "Cannot combine --stdin with input file \"\(inputPath)\".")
        }
        if mode == .render, recursiveBatch {
            throw CLIError.incompatibleOptions("Cannot combine render with --recursive.")
        }
        if mode == .render, failOnSkipped {
            throw CLIError.incompatibleOptions("Cannot combine render with --fail-on-skipped.")
        }
        if mode == .render, failOnEmpty {
            throw CLIError.incompatibleOptions("Cannot combine render with --fail-on-empty.")
        }
        if mode == .render, skippedReportPath != nil {
            throw CLIError.incompatibleOptions("Cannot combine render with --skipped-report.")
        }
        if mode == .render, batchManifestPath != nil {
            throw CLIError.incompatibleOptions("Cannot combine render with --manifest.")
        }
        if mode == .render, dryRunBatch {
            throw CLIError.incompatibleOptions("Cannot combine render with --dry-run.")
        }
        if mode == .render, !batchIncludeExtensions.isEmpty {
            throw CLIError.incompatibleOptions("Cannot combine render with --include-ext.")
        }
        if mode == .render, !batchExcludeExtensions.isEmpty {
            throw CLIError.incompatibleOptions("Cannot combine render with --exclude-ext.")
        }
        let metadataHeaderRequested =
            windowTitle != nil || metadataFilename != nil
            || metadataTitle != nil || metadataCaption != nil || showLanguageBadge
        let styleOptionsRequested =
            background != nil || transparent || fontName != nil || fontLigatures != nil
            || fontSize != nil || padding != nil
            || cornerRadius != nil || shadowRadius != nil || wrapColumns != nil
            || formatCode
            || showLineNumbers != nil || showChrome != nil || showShadow != nil
            || highlightedLineRanges != nil || redactedLineRanges != nil
            || redactSecrets || focusHighlightedLines != nil || diffDecorations != nil

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
            if htmlSidecar {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with --html-sidecar.")
            }
            if metadataHeaderRequested {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with metadata header options.")
            }
            if wrapColumns != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with --wrap-columns.")
            }
            if styleOptionsRequested {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --edit with render-only style options.")
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
        if htmlSidecar, outputPath == nil {
            throw CLIError.incompatibleOptions(
                "--html-sidecar needs an --out path to write beside.")
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

        let resolvedFormat = try resolveFormat(
            explicitFormat, command: mode, outputPath: resolvedOutput)

        return CLIOptions(
            command: mode,
            quiet: quiet,
            jsonOutput: jsonOutput,
            inputPath: resolvedInput,
            outputPath: resolvedOutput,
            themeID: themeID,
            language: languageID.flatMap(Language.init(rawValue:)),
            presetID: presetID,
            scale: scale,
            fontName: fontName,
            fontLigatures: fontLigatures,
            fontSize: fontSize,
            padding: padding,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            terminalColumns: terminalColumns,
            wrapColumns: wrapColumns,
            formatCode: formatCode,
            format: resolvedFormat,
            profile: profile,
            transparent: transparent,
            background: background,
            noOverwrite: noOverwrite,
            windowTitle: windowTitle,
            metadataFilename: metadataFilename,
            stdinFilename: stdinFilename,
            metadataTitle: metadataTitle,
            metadataCaption: metadataCaption,
            showLanguageBadge: showLanguageBadge,
            showLineNumbers: showLineNumbers,
            showChrome: showChrome,
            showShadow: showShadow,
            highlightedLineRanges: highlightedLineRanges,
            redactedLineRanges: redactedLineRanges,
            redactSecrets: redactSecrets,
            focusHighlightedLines: focusHighlightedLines,
            diffDecorations: diffDecorations,
            recursiveBatch: recursiveBatch,
            failOnSkipped: failOnSkipped,
            failOnEmpty: failOnEmpty,
            skippedReportPath: skippedReportPath,
            batchManifestPath: batchManifestPath,
            dryRunBatch: dryRunBatch,
            batchIncludeExtensions: batchIncludeExtensions,
            batchExcludeExtensions: batchExcludeExtensions,
            readStdin: readStdin,
            copyToClipboard: copyToClipboard,
            openInEditor: openInEditor,
            textSidecar: textSidecar,
            markdownSidecar: markdownSidecar,
            htmlSidecar: htmlSidecar
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

    /// Validates a code font family against the same catalog exposed in the editor.
    private static func resolveFont(_ raw: String) throws -> String {
        guard CodeFont.all.contains(raw) else {
            throw CLIError.invalidValue(flag: "--font", value: raw)
        }
        return raw
    }

    /// Validates a gradient id against the same built-in catalog exposed by
    /// `vitrine list backgrounds`.
    private static func resolveBackground(_ raw: String) throws -> GradientPreset {
        guard
            let preset = GradientPreset.allCases.first(where: {
                $0.rawValue.lowercased() == raw
            })
        else {
            throw CLIError.invalidValue(flag: "--background", value: raw)
        }
        return preset
    }

    /// Parses a CSS-style RGB/RGBA hex value into the model's fixed-sRGB color type.
    private static func resolveBackgroundColor(_ raw: String) throws -> RGBAColor {
        guard let color = RGBAColor(hex: raw) else {
            throw CLIError.invalidValue(flag: "--background-color", value: raw)
        }
        return color
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

    /// Parses and range-checks the code font size in points (Style pane bounds).
    private static func resolveFontSize(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.fontSizeRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the canvas padding in points (Style pane bounds).
    private static func resolvePadding(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.paddingRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the code-card corner radius in points.
    private static func resolveCornerRadius(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.cornerRadiusRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the drop-shadow blur radius in points.
    private static func resolveShadowRadius(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.shadowRadiusRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses a strict, 1-based line range list (for example `3,7-9,12`). Unlike the
    /// editor's forgiving text field, the CLI rejects malformed fragments so automation
    /// cannot silently render the wrong emphasized rows.
    private static func resolveLineRanges(
        _ raw: String, flag: String
    ) throws -> [ClosedRange<Int>] {
        let fragments = raw.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "," || $0 == "\n" })
        guard !fragments.isEmpty else { throw CLIError.invalidValue(flag: flag, value: raw) }

        var ranges: [ClosedRange<Int>] = []
        for fragment in fragments {
            let trimmed = fragment.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw CLIError.invalidValue(flag: flag, value: raw)
            }

            let bounds = trimmed.split(separator: "-", omittingEmptySubsequences: false)
            switch bounds.count {
            case 1:
                guard let line = positiveLine(bounds[0]) else {
                    throw CLIError.invalidValue(flag: flag, value: raw)
                }
                ranges.append(line...line)
            case 2:
                guard let low = positiveLine(bounds[0]), let high = positiveLine(bounds[1]) else {
                    throw CLIError.invalidValue(flag: flag, value: raw)
                }
                ranges.append(min(low, high)...max(low, high))
            default:
                throw CLIError.invalidValue(flag: flag, value: raw)
            }
        }

        return LineHighlight.normalize(ranges)
    }

    private static func positiveLine(_ text: Substring) -> Int? {
        guard
            let value = Int(text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)),
            value >= 1
        else {
            return nil
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

    /// Resolves the output format for a command after all flags are parsed.
    ///
    /// A single-file `render` can infer the format from a known output extension, which
    /// keeps `vitrine render source.swift --out card.pdf` from writing PNG bytes into a
    /// `.pdf` path. If the user passes both `--format` and a known extension, they must
    /// agree so automation never produces misleading artifacts. `batch` writes into a
    /// folder and derives each output extension from the chosen format, so its directory
    /// name is intentionally ignored here.
    private static func resolveFormat(
        _ explicitFormat: ExportFormat?, command: CLIOptions.Command, outputPath: String
    ) throws -> ExportFormat {
        guard command == .render, !outputPath.isEmpty else { return explicitFormat ?? .png }

        let outputExtension = URL(fileURLWithPath: outputPath).pathExtension.lowercased()
        guard let extensionFormat = ExportFormat(rawValue: outputExtension) else {
            return explicitFormat ?? .png
        }

        if let explicitFormat {
            guard explicitFormat == extensionFormat else {
                throw CLIError.incompatibleOptions(
                    "Output extension .\(outputExtension) does not match --format \(explicitFormat.rawValue)."
                )
            }
            return explicitFormat
        }
        return extensionFormat
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

    /// Parses a comma-separated batch extension list, accepting either `swift` or
    /// `.swift` spellings and normalizing everything to lowercase without the dot.
    private static func resolveExtensionList(_ raw: String, flag: String) throws -> Set<String> {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let parts =
            raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !parts.isEmpty else { throw CLIError.invalidValue(flag: flag, value: raw) }

        var extensions: Set<String> = []
        for part in parts {
            let normalized = part.hasPrefix(".") ? String(part.dropFirst()) : part
            guard !normalized.isEmpty,
                normalized.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) })
            else {
                throw CLIError.invalidValue(flag: flag, value: raw)
            }
            extensions.insert(normalized.lowercased())
        }
        return extensions
    }

    /// Parses the convenience sidecar bundle list. Comma-separated values compose
    /// with the explicit `--*-sidecar` flags, so scripts can say `--sidecars all` or
    /// keep enabling individual sidecars as their needs grow.
    private static func resolveSidecars(
        _ raw: String, flag: String
    ) throws -> (text: Bool, markdown: Bool, html: Bool) {
        var result = (text: false, markdown: false, html: false)
        let parts =
            raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard !parts.isEmpty else { throw CLIError.invalidValue(flag: flag, value: raw) }

        for part in parts {
            switch part {
            case "all":
                result = (text: true, markdown: true, html: true)
            case "text", "txt":
                result.text = true
            case "markdown", "md":
                result.markdown = true
            case "html":
                result.html = true
            default:
                throw CLIError.invalidValue(flag: flag, value: raw)
            }
        }
        return result
    }
}

/// The `vitrine` usage text, shown for `--help` and on a usage error.
///
/// `nonisolated` (a pure static string) so `CLIError.message` — itself nonisolated —
/// can compose it, and so the executable and tests can read it from any context.
nonisolated enum CLIUsage {
    static let text = """
        vitrine — render code to an image from the command line.

        USAGE:
          vitrine render <input-file> --out <image> [options]
          vitrine render --stdin --copy [options]
          vitrine render --stdin --out <image> [--stdin-name <name>] [options]
          vitrine render (<input-file> | --stdin) --edit [options]
          vitrine batch <input-folder> --out <output-folder> [options]
          vitrine list <all|themes|languages|presets|fonts|backgrounds|formats|profiles> [--json]
          vitrine --version [--json]
          vitrine version [--json]
          vitrine shell-init [zsh|bash|fish]   Print the terminal-capture shell helpers.

        OPTIONS:
          -o, --out <path>       Output image path (required unless --copy / --edit).
          -q, --quiet            Suppress success output; errors still print.
          --json                 Print render/batch success output or metadata as JSON
                                 (render/batch: not with --quiet).
          --copy                 Copy the rendered image to the clipboard.
          -e, --edit             Open the source in Vitrine's editor instead of
                                 rendering (no image is written; not with --copy/--out).
          --stdin                Read the source from standard input (e.g. a pipe).
          --stdin-name <name>    With --stdin, infer language and default metadata
                                 from this filename; no file is read.
          --theme <id>           Syntax theme id (e.g. one-dark, dracula, nord).
          --language <id>        Language id (e.g. swift, python, terminal). Inferred
                                 when omitted.
          --preset <id>          Destination preset (twitter, linkedin, keynote,
                                 docs, transparent-slide, opengraph).
          --scale <1|2|3>        Export resolution multiplier. Defaults to the app
                                 default, or the preset's recommended scale.
          --font <family>        Code font family. Use `vitrine list fonts`.
          --font-ligatures       Enable programming ligatures when the font supports them.
          --no-font-ligatures    Disable programming ligatures.
          --font-size <n>        Code font size in points (10-20).
          --padding <n>          Canvas padding in points (16-64).
          --corner-radius <n>    Code-card corner radius in points (0-48).
          --shadow-radius <n>    Drop-shadow blur radius in points (0-40).
          --terminal-width <n>   Reconstruct terminal output at exactly n columns
                                 instead of inferring the width (1-1000). Only
                                 affects --language terminal; set by `vgrab -w`.
          --wrap-columns <n>     Soft-wrap long code lines at n columns (40-200).
          --format-code          Tidy indentation locally before rendering
                                 (--tidy is also accepted).
          --format <png|pdf|heic>  Output format. Defaults to png; pdf is the vector
                                 option, heic the compact raster one.
          --profile <srgb|p3>    PNG color profile. Defaults to srgb.
          --transparent          Render a real transparent background.
          --background <id>      Built-in gradient. Use `vitrine list backgrounds`.
          --background-color <hex>
                                 Solid RGB/RGBA hex color (for example '#1E293B').
          --no-overwrite         Refuse to replace existing image/sidecar outputs
                                 (--no-clobber is also accepted).
          --window-title <text>  Title shown in the rendered window chrome.
          --filename <text>      Filename chip shown in the metadata header.
          --title <text>         Title shown in the metadata header.
          --caption <text>       Caption shown below the metadata title.
          --language-badge       Show the language badge in the metadata header.
          --line-numbers         Show the line-number gutter.
          --no-line-numbers      Hide the line-number gutter.
          --chrome / --no-chrome Show or hide the rendered window chrome.
          --shadow / --no-shadow Show or hide the rendered drop shadow.
          --highlight-lines <spec>
                                 Highlight 1-based lines/ranges (for example
                                 3,7-9,12).
          --redact-lines <spec>  Redact 1-based lines/ranges; sidecars replace
                                 them with [redacted].
          --redact-secrets       Scan for likely secrets and redact matching rows.
          --focus-lines / --no-focus-lines
                                 Dim or undim non-highlighted rows.
          --diff-bands / --no-diff-bands
                                 Show or hide GitHub-style diff line bands.
          --recursive            Batch only: include nested folders and preserve
                                 relative output paths.
          --fail-on-skipped      Batch only: exit non-zero if any file is skipped.
          --fail-on-empty        Batch only: exit non-zero when no files would render.
          --skipped-report <json>
                                 Batch only: write skipped files as a JSON report.
          --manifest <json>      Batch only: write rendered/planned outputs as JSON.
          --dry-run              Batch only: scan/load inputs without writing images.
          --include-ext <list>   Batch only: only render these comma-separated
                                 extensions (for example swift,md).
          --exclude-ext <list>   Batch only: ignore these comma-separated extensions
                                 before loading files.
          --text-sidecar         Also write a .txt next to --out with the source as
                                 selectable text (terminal escapes stripped).
          --markdown-sidecar     Also write a .md next to --out: the image reference
                                 plus the source in a fenced code block, ready to
                                 paste into a README or post.
          --html-sidecar         Also write a .html next to --out: the image embed
                                 plus escaped source in a <pre><code> block.
          --sidecars <list>      Enable sidecars by comma-separated list: text,
                                 markdown, html, or all.
          -h, --help             Show this help.

        Code rendering is fully local: it never needs the network, screen recording,
        or Accessibility permissions.
        """
}
