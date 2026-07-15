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
    /// `--image` input decoded as bytes but is not an image supported by AppKit.
    case inputNotImage(path: String)
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
        case .inputNotImage(let path):
            "The input file at \"\(path)\" is not a supported image."
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
        var imageInputPath: String?
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
        var backgroundImagePath: String?
        var backgroundImageFit: BackgroundFit?
        var backgroundImageBlur: Double?
        var backgroundImageDimming: Double?
        var gradientBackgroundRequested = false
        var solidBackgroundRequested = false
        var customGradientColors: [RGBAColor]?
        var customGradientAngle: Double?
        var watermarkText: String?
        var watermarkLogoPath: String?
        var watermarkColor: RGBAColor?
        var watermarkPosition: CLIOptions.WatermarkPosition?
        var watermarkX: Double?
        var watermarkY: Double?
        var calloutText: String?
        var calloutX: Double?
        var calloutY: Double?
        var calloutColor: RGBAColor?
        var calloutSize: Double?
        var counterNumber: Int?
        var counterX: Double?
        var counterY: Double?
        var counterColor: RGBAColor?
        var counterSize: Double?
        var arrowStart: CGPoint?
        var arrowEnd: CGPoint?
        var arrowColor: RGBAColor?
        var arrowSize: Double?
        var lineStart: CGPoint?
        var lineEnd: CGPoint?
        var lineColor: RGBAColor?
        var lineSize: Double?
        var imageFrame: CLIOptions.ImageFrameOption?
        var frameAppearance: CLIOptions.ImageFrameAppearance?
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
            case "--image":
                imageInputPath = try value(for: token)
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
            case "--background-gradient":
                customGradientColors = try resolveCustomGradientColors(try value(for: token))
            case "--background-angle":
                customGradientAngle = try resolveBackgroundAngle(try value(for: token))
            case "--background-image":
                backgroundImagePath = try value(for: token)
            case "--background-fit":
                backgroundImageFit = try resolveBackgroundFit(try value(for: token))
            case "--background-blur":
                backgroundImageBlur = try resolveBackgroundBlur(try value(for: token), flag: token)
            case "--background-dimming":
                backgroundImageDimming = try resolveBackgroundDimming(
                    try value(for: token), flag: token)
            case "--watermark":
                watermarkText = try resolveWatermarkText(try value(for: token))
            case "--watermark-logo":
                watermarkLogoPath = try value(for: token)
            case "--watermark-color":
                watermarkColor = try resolveWatermarkColor(try value(for: token))
            case "--watermark-position":
                watermarkPosition = try resolveWatermarkPosition(try value(for: token))
            case "--watermark-x":
                watermarkX = try resolveNormalizedCoordinate(try value(for: token), flag: token)
            case "--watermark-y":
                watermarkY = try resolveNormalizedCoordinate(try value(for: token), flag: token)
            case "--callout":
                calloutText = try resolveCalloutText(try value(for: token))
            case "--callout-x":
                calloutX = try resolveNormalizedCoordinate(try value(for: token), flag: token)
            case "--callout-y":
                calloutY = try resolveNormalizedCoordinate(try value(for: token), flag: token)
            case "--callout-color":
                calloutColor = try resolveCalloutColor(try value(for: token))
            case "--callout-size":
                calloutSize = try resolveCalloutSize(try value(for: token))
            case "--counter":
                counterNumber = try resolveCounterNumber(try value(for: token))
            case "--counter-x":
                counterX = try resolveNormalizedCoordinate(try value(for: token), flag: token)
            case "--counter-y":
                counterY = try resolveNormalizedCoordinate(try value(for: token), flag: token)
            case "--counter-color":
                counterColor = try resolveHexColor(try value(for: token), flag: token)
            case "--counter-size":
                counterSize = try resolveAnnotationSize(try value(for: token), flag: token)
            case "--arrow":
                let segment = try resolveNormalizedSegment(try value(for: token), flag: token)
                arrowStart = segment.start
                arrowEnd = segment.end
            case "--arrow-color":
                arrowColor = try resolveHexColor(try value(for: token), flag: token)
            case "--arrow-size":
                arrowSize = try resolveAnnotationSize(try value(for: token), flag: token)
            case "--line":
                let segment = try resolveNormalizedSegment(try value(for: token), flag: token)
                lineStart = segment.start
                lineEnd = segment.end
            case "--line-color":
                lineColor = try resolveHexColor(try value(for: token), flag: token)
            case "--line-size":
                lineSize = try resolveAnnotationSize(try value(for: token), flag: token)
            case "--frame":
                imageFrame = try resolveImageFrame(try value(for: token))
            case "--frame-appearance":
                frameAppearance = try resolveFrameAppearance(try value(for: token))
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

        // `--stdin`, image-input controls, stdin filename hints, `--copy`, and `--edit`
        // are render-only (a batch needs real folders).
        if mode == .batch,
            readStdin || imageInputPath != nil || stdinFilename != nil || copyToClipboard
                || openInEditor || imageFrame != nil || frameAppearance != nil
        {
            let flag: String
            if readStdin {
                flag = "--stdin"
            } else if imageInputPath != nil {
                flag = "--image"
            } else if stdinFilename != nil {
                flag = "--stdin-name"
            } else if copyToClipboard {
                flag = "--copy"
            } else if openInEditor {
                flag = "--edit"
            } else if imageFrame != nil {
                flag = "--frame"
            } else {
                flag = "--frame-appearance"
            }
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
        if customGradientColors != nil, gradientBackgroundRequested || solidBackgroundRequested {
            throw CLIError.incompatibleOptions(
                "Cannot combine --background-gradient with --background or --background-color.")
        }
        if transparent, background != nil {
            throw CLIError.incompatibleOptions(
                "Cannot combine --transparent with --background or --background-color.")
        }
        if transparent, customGradientColors != nil {
            throw CLIError.incompatibleOptions(
                "Cannot combine --transparent with --background-gradient.")
        }
        if customGradientColors == nil, customGradientAngle != nil {
            throw CLIError.incompatibleOptions(
                "--background-angle requires --background-gradient.")
        }
        if backgroundImagePath != nil,
            transparent || background != nil || customGradientColors != nil
        {
            throw CLIError.incompatibleOptions(
                "Cannot combine --background-image with another background option.")
        }
        if backgroundImagePath == nil {
            if backgroundImageFit != nil {
                throw CLIError.incompatibleOptions("--background-fit requires --background-image.")
            }
            if backgroundImageBlur != nil {
                throw CLIError.incompatibleOptions("--background-blur requires --background-image.")
            }
            if backgroundImageDimming != nil {
                throw CLIError.incompatibleOptions(
                    "--background-dimming requires --background-image.")
            }
        }
        if let customGradientColors {
            background = .customGradient(
                makeCustomGradient(colors: customGradientColors, angle: customGradientAngle))
        }
        let watermarkContentRequested = watermarkText != nil || watermarkLogoPath != nil
        if watermarkText == nil, watermarkColor != nil {
            throw CLIError.incompatibleOptions(
                "--watermark-color requires --watermark text.")
        }
        if !watermarkContentRequested, watermarkPosition != nil {
            throw CLIError.incompatibleOptions(
                "--watermark-position requires --watermark or --watermark-logo.")
        }
        if !watermarkContentRequested, watermarkX != nil || watermarkY != nil {
            throw CLIError.incompatibleOptions(
                "--watermark-x and --watermark-y require --watermark or --watermark-logo.")
        }
        if (watermarkX == nil) != (watermarkY == nil) {
            throw CLIError.incompatibleOptions(
                "--watermark-x and --watermark-y must be provided together.")
        }
        if watermarkPosition == .free, watermarkX == nil {
            throw CLIError.incompatibleOptions(
                "--watermark-position free requires --watermark-x and --watermark-y.")
        }
        if watermarkX != nil, watermarkPosition != .free {
            throw CLIError.incompatibleOptions(
                "--watermark-x and --watermark-y require --watermark-position free.")
        }
        if calloutText == nil,
            calloutX != nil || calloutY != nil || calloutColor != nil || calloutSize != nil
        {
            throw CLIError.incompatibleOptions(
                "--callout-x, --callout-y, --callout-color, and --callout-size require --callout.")
        }
        if (calloutX == nil) != (calloutY == nil) {
            throw CLIError.incompatibleOptions(
                "--callout-x and --callout-y must be provided together.")
        }
        if counterNumber == nil,
            counterX != nil || counterY != nil || counterColor != nil || counterSize != nil
        {
            throw CLIError.incompatibleOptions(
                "--counter-x, --counter-y, --counter-color, and --counter-size require --counter.")
        }
        if (counterX == nil) != (counterY == nil) {
            throw CLIError.incompatibleOptions(
                "--counter-x and --counter-y must be provided together.")
        }
        if arrowStart == nil, arrowColor != nil || arrowSize != nil {
            throw CLIError.incompatibleOptions(
                "--arrow-color and --arrow-size require --arrow.")
        }
        if lineStart == nil, lineColor != nil || lineSize != nil {
            throw CLIError.incompatibleOptions(
                "--line-color and --line-size require --line.")
        }
        if imageInputPath == nil, imageFrame != nil || frameAppearance != nil {
            throw CLIError.incompatibleOptions(
                "--frame and --frame-appearance require --image.")
        }
        if readStdin, let inputPath {
            throw CLIError.incompatibleOptions(
                "Cannot combine --stdin with input file \"\(inputPath)\".")
        }
        if imageInputPath != nil, let inputPath {
            throw CLIError.incompatibleOptions(
                "Cannot combine --image with input file \"\(inputPath)\".")
        }
        if imageInputPath != nil, readStdin {
            throw CLIError.incompatibleOptions("Cannot combine --image with --stdin.")
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
            background != nil || backgroundImagePath != nil || transparent || fontName != nil
            || fontLigatures != nil
            || fontSize != nil || padding != nil
            || cornerRadius != nil || shadowRadius != nil || wrapColumns != nil
            || formatCode
            || watermarkContentRequested
            || calloutText != nil
            || counterNumber != nil
            || arrowStart != nil
            || lineStart != nil
            || showLineNumbers != nil || showChrome != nil || showShadow != nil
            || highlightedLineRanges != nil || redactedLineRanges != nil
            || redactSecrets || focusHighlightedLines != nil || diffDecorations != nil

        if imageInputPath != nil {
            if openInEditor {
                throw CLIError.incompatibleOptions("Cannot combine --image with --edit.")
            }
            let codeOnlyOptionsRequested =
                themeID != nil || languageID != nil || fontName != nil || fontLigatures != nil
                || fontSize != nil || terminalColumns != nil || wrapColumns != nil || formatCode
                || metadataFilename != nil || metadataTitle != nil
                || metadataCaption != nil || showLanguageBadge || showLineNumbers != nil
                || showChrome != nil || highlightedLineRanges != nil || redactedLineRanges != nil
                || redactSecrets || focusHighlightedLines != nil || diffDecorations != nil
                || textSidecar || markdownSidecar || htmlSidecar
            if codeOnlyOptionsRequested {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --image with code-only or sidecar options.")
            }
            if frameAppearance != nil,
                imageFrame == nil || imageFrame == CLIOptions.ImageFrameOption.none
            {
                throw CLIError.incompatibleOptions(
                    "--frame-appearance requires --frame with a framed image.")
            }
            if windowTitle != nil, imageFrame?.supportsWindowTitle != true {
                throw CLIError.incompatibleOptions(
                    "--window-title with --image requires --frame macos-window or browser.")
            }
        }

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
        // Input is a code file, local image, or stdin; output is required unless copying the
        // image to the clipboard or handing it to the editor (`--edit`), neither of
        // which writes a file.
        let resolvedInput: String
        if let imageInputPath {
            resolvedInput = imageInputPath
        } else if readStdin {
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
        let watermarkFreePosition: CGPoint? =
            if let watermarkX, let watermarkY {
                CGPoint(x: watermarkX, y: watermarkY)
            } else {
                nil
            }
        let calloutPosition: CGPoint? =
            if let calloutX, let calloutY {
                CGPoint(x: calloutX, y: calloutY)
            } else {
                nil
            }
        let counterPosition: CGPoint? =
            if let counterX, let counterY {
                CGPoint(x: counterX, y: counterY)
            } else {
                nil
            }
        let arrow: CLIOptions.SegmentAnnotation? =
            if let arrowStart, let arrowEnd {
                CLIOptions.SegmentAnnotation(
                    start: arrowStart, end: arrowEnd, color: arrowColor, size: arrowSize)
            } else {
                nil
            }
        let line: CLIOptions.SegmentAnnotation? =
            if let lineStart, let lineEnd {
                CLIOptions.SegmentAnnotation(
                    start: lineStart, end: lineEnd, color: lineColor, size: lineSize)
            } else {
                nil
            }

        return CLIOptions(
            command: mode,
            quiet: quiet,
            jsonOutput: jsonOutput,
            inputKind: imageInputPath == nil ? .code : .image,
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
            backgroundImagePath: backgroundImagePath,
            backgroundImageFit: backgroundImageFit,
            backgroundImageBlur: backgroundImageBlur,
            backgroundImageDimming: backgroundImageDimming,
            watermarkText: watermarkText,
            watermarkLogoPath: watermarkLogoPath,
            watermarkColor: watermarkColor,
            watermarkPosition: watermarkPosition,
            watermarkFreePosition: watermarkFreePosition,
            calloutText: calloutText,
            calloutPosition: calloutPosition,
            calloutColor: calloutColor,
            calloutSize: calloutSize,
            counterNumber: counterNumber,
            counterPosition: counterPosition,
            counterColor: counterColor,
            counterSize: counterSize,
            arrow: arrow,
            line: line,
            imageFrame: imageFrame,
            frameAppearance: frameAppearance,
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

    /// Parses at least two comma-separated RGB/RGBA colors for a custom gradient.
    private static func resolveCustomGradientColors(_ raw: String) throws -> [RGBAColor] {
        let components = raw.split(separator: ",", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard components.count >= 2 else {
            throw CLIError.invalidValue(flag: "--background-gradient", value: raw)
        }
        let colors = components.compactMap(RGBAColor.init(hex:))
        guard colors.count == components.count else {
            throw CLIError.invalidValue(flag: "--background-gradient", value: raw)
        }
        return colors
    }

    /// Parses the editor's supported custom-gradient angle range.
    private static func resolveBackgroundAngle(_ raw: String) throws -> Double {
        guard let angle = Double(raw), angle.isFinite, (0...360).contains(angle) else {
            throw CLIError.invalidValue(flag: "--background-angle", value: raw)
        }
        return angle
    }

    /// Spreads CLI colors evenly across the gradient axis, matching preset conversion.
    private static func makeCustomGradient(colors: [RGBAColor], angle: Double?) -> CustomGradient {
        let lastIndex = Double(colors.count - 1)
        let stops = colors.enumerated().map { index, color in
            GradientStop(color: color, location: Double(index) / lastIndex)
        }
        return CustomGradient(stops: stops, angle: angle ?? CustomGradient.default.angle)
    }

    /// Resolves the app's stable local image-background sizing behavior.
    private static func resolveBackgroundFit(_ raw: String) throws -> BackgroundFit {
        guard let fit = BackgroundFit(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--background-fit", value: raw)
        }
        return fit
    }

    /// Parses the image-background blur range exposed by the editor.
    private static func resolveBackgroundBlur(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, ImageBackground.blurRange.contains(value)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses the normalized image-background dimming range exposed by the editor.
    private static func resolveBackgroundDimming(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, ImageBackground.dimmingRange.contains(value)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Normalizes the text in the same way as Brand Kit fields and rejects a blank
    /// badge so a successful command can never silently render no watermark.
    private static func resolveWatermarkText(_ raw: String) throws -> String {
        try resolveVisibleText(raw, flag: "--watermark")
    }

    /// Parses a CSS-style RGB/RGBA hex tint for the watermark text.
    private static func resolveWatermarkColor(_ raw: String) throws -> RGBAColor {
        try resolveHexColor(raw, flag: "--watermark-color")
    }

    /// Resolves one of the stable corner ids advertised by the watermark-position catalog.
    private static func resolveWatermarkPosition(
        _ raw: String
    ) throws -> CLIOptions.WatermarkPosition {
        guard let position = CLIOptions.WatermarkPosition(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--watermark-position", value: raw)
        }
        return position
    }

    /// Parses a normalized canvas coordinate for deterministic free watermark placement.
    private static func resolveNormalizedCoordinate(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, (0...1).contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Normalizes callout copy and rejects blank content that would render no mark.
    private static func resolveCalloutText(_ raw: String) throws -> String {
        try resolveVisibleText(raw, flag: "--callout")
    }

    /// Trims user-facing badge copy and rejects values that cannot produce pixels.
    private static func resolveVisibleText(_ raw: String, flag: String) throws -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return normalized
    }

    /// Parses the same fixed-sRGB hex color accepted by the annotation toolbar model.
    private static func resolveCalloutColor(_ raw: String) throws -> RGBAColor {
        try resolveHexColor(raw, flag: "--callout-color")
    }

    /// Parses a CSS-style fixed-sRGB color for any CLI overlay control.
    private static func resolveHexColor(_ raw: String, flag: String) throws -> RGBAColor {
        guard let color = RGBAColor(hex: raw) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return color
    }

    /// Parses the editor annotation toolbar's supported size-weight range.
    private static func resolveCalloutSize(_ raw: String) throws -> Double {
        try resolveAnnotationSize(raw, flag: "--callout-size")
    }

    /// Parses an annotation size using the editor toolbar's shared bounds.
    private static func resolveAnnotationSize(_ raw: String, flag: String) throws -> Double {
        guard let size = Double(raw), size.isFinite, Annotation.thicknessRange.contains(size) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return size
    }

    /// Parses a compact positive counter label that remains legible in the badge.
    private static func resolveCounterNumber(_ raw: String) throws -> Int {
        guard let number = Int(raw), CLIOptions.counterNumberRange.contains(number) else {
            throw CLIError.invalidValue(flag: "--counter", value: raw)
        }
        return number
    }

    /// Parses two normalized endpoints and rejects invisible zero-length marks.
    private static func resolveNormalizedSegment(
        _ raw: String, flag: String
    ) throws -> (start: CGPoint, end: CGPoint) {
        let components = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == 4 else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        let values = components.compactMap { component -> Double? in
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), value.isFinite, (0...1).contains(value) else {
                return nil
            }
            return value
        }
        guard values.count == 4 else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        let start = CGPoint(x: values[0], y: values[1])
        let end = CGPoint(x: values[2], y: values[3])
        guard start != end else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return (start, end)
    }

    /// Resolves a stable image-frame id advertised by `vitrine list frames`.
    private static func resolveImageFrame(_ raw: String) throws -> CLIOptions.ImageFrameOption {
        guard let frame = CLIOptions.ImageFrameOption(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--frame", value: raw)
        }
        return frame
    }

    /// Resolves a stable frame-appearance id advertised by the CLI catalog.
    private static func resolveFrameAppearance(
        _ raw: String
    ) throws -> CLIOptions.ImageFrameAppearance {
        guard let appearance = CLIOptions.ImageFrameAppearance(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--frame-appearance", value: raw)
        }
        return appearance
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
          vitrine render --image <input-image> --out <image> [options]
          vitrine render --stdin --copy [options]
          vitrine render --stdin --out <image> [--stdin-name <name>] [options]
          vitrine render (<input-file> | --stdin) --edit [options]
          vitrine batch <input-folder> --out <output-folder> [options]
          vitrine list <all|themes|languages|presets|fonts|backgrounds|background-fits|frames|frame-appearances|watermark-positions|formats|profiles> [--json]
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
          --image <path>         Beautify a local image instead of rendering code.
          --frame <id>           Frame for --image: none, macos-window, browser,
                                 macbook, or iphone. Use `vitrine list frames`.
          --frame-appearance <id>
                                 Framed-image chrome: auto, light, or dark.
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
          --background-gradient <hex,hex,...>
                                 Custom gradient with two or more RGB/RGBA colors.
          --background-angle <degrees>
                                 Custom gradient angle from 0 through 360; requires
                                 --background-gradient (defaults to 135).
          --background-image <path>
                                 Local image used as the canvas background.
          --background-fit <fill|fit>
                                 Sizing for --background-image (defaults to fill).
          --background-blur <0...40>
                                 Blur radius for --background-image in points.
          --background-dimming <0...1>
                                 Dark overlay strength for --background-image.
          --watermark <text>     Add text to the rendered watermark badge.
          --watermark-logo <path>
                                 Add a local image to the watermark badge.
          --watermark-color <hex>
                                 Watermark text tint; requires --watermark.
          --watermark-position <corner|free>
                                 Watermark placement: bottom-right, bottom-left,
                                 top-right, top-left, or free; requires watermark
                                 text or a logo.
          --watermark-x <0...1>  Normalized horizontal center for free placement.
          --watermark-y <0...1>  Normalized vertical center for free placement; x/y
                                 must be provided together with position free.
          --callout <text>       Add a text callout through the annotation layer.
          --callout-x <0...1>    Normalized horizontal anchor (defaults to 0.5).
          --callout-y <0...1>    Normalized vertical anchor (defaults to 0.5); x/y
                                 must be provided together.
          --callout-color <hex>  Callout RGB/RGBA text color; requires --callout.
          --callout-size <2...28>
                                 Callout size weight; requires --callout.
          --counter <1...99>     Add a numbered annotation badge.
          --counter-x <0...1>    Normalized horizontal center (defaults to 0.5).
          --counter-y <0...1>    Normalized vertical center (defaults to 0.5); x/y
                                 must be provided together.
          --counter-color <hex>  Counter RGB/RGBA fill color; requires --counter.
          --counter-size <2...28>
                                 Counter size weight; requires --counter.
          --arrow <x1,y1,x2,y2> Add an arrow from normalized tail to head coordinates.
          --arrow-color <hex>   Arrow RGB/RGBA stroke color; requires --arrow.
          --arrow-size <2...28> Arrow stroke weight; requires --arrow.
          --line <x1,y1,x2,y2>  Add a line between normalized canvas coordinates.
          --line-color <hex>    Line RGB/RGBA stroke color; requires --line.
          --line-size <2...28>  Line stroke weight; requires --line.
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
