import Foundation

/// Mutable state for one CLI invocation. It owns token consumption and records
/// syntactically valid flag values; semantic compatibility is resolved separately.
struct CLIArgumentParser {
    var remaining: ArraySlice<String>
    let mode: CLIOptions.Command

    var inputPath: String?
    var imageInputPath: String?
    var outputPath: String?
    var quiet = false
    var jsonOutput = false
    var themeID: String?
    var languageID: String?
    var presetID: String?
    var multiSizePresetIDs: Set<String> = []
    var stylePresetID: String?
    var canvasSize: CGSize?
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
    var arrowSegments: [(start: CGPoint, end: CGPoint)] = []
    var arrowColor: RGBAColor?
    var arrowSize: Double?
    var lineSegments: [(start: CGPoint, end: CGPoint)] = []
    var lineColor: RGBAColor?
    var lineSize: Double?
    var rectangleRegions: [(start: CGPoint, end: CGPoint)] = []
    var rectangleColor: RGBAColor?
    var rectangleSize: Double?
    var highlighterRegions: [(start: CGPoint, end: CGPoint)] = []
    var highlighterColor: RGBAColor?
    var blurBoxRegions: [(start: CGPoint, end: CGPoint)] = []
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
    var gitDiffSource: GitDiffInputLoader.Source?
    var gitDiffPaths: [String] = []
    var gitDiffContextLines: Int?
    var copyToClipboard = false
    var openInEditor = false
    var textSidecar = false
    var markdownSidecar = false
    var htmlSidecar = false

    init(_ arguments: [String]) throws {
        let remaining = ArraySlice(arguments)

        guard let command = remaining.first else { throw CLIError.helpRequested }
        if command == "--help" || command == "-h" { throw CLIError.helpRequested }

        let mode: CLIOptions.Command
        switch command {
        case "render": mode = .render
        case "multi-size": mode = .multiSize
        case "batch": mode = .batch
        default: throw CLIError.unknownCommand(command)
        }

        self.remaining = remaining.dropFirst()
        self.mode = mode
    }

    mutating func parse() throws -> CLIOptions {
        try parseTokens()
        return try resolvedOptions()
    }

    /// Pops the value that must follow a `--flag`, or throws if it is absent.
    mutating func value(for flag: String) throws -> String {
        guard let next = remaining.first else { throw CLIError.missingValue(flag: flag) }
        remaining = remaining.dropFirst()
        return next
    }

    mutating func parseTokens() throws {
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
            case "--presets":
                multiSizePresetIDs.formUnion(
                    try resolvePresetList(try value(for: token), flag: token))
            case "--style-preset":
                stylePresetID = try resolveStylePreset(try value(for: token))
            case "--canvas-size":
                canvasSize = try resolveCanvasSize(try value(for: token), flag: token)
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
                arrowSegments.append(
                    try resolveNormalizedSegment(try value(for: token), flag: token))
            case "--arrow-color":
                arrowColor = try resolveHexColor(try value(for: token), flag: token)
            case "--arrow-size":
                arrowSize = try resolveAnnotationSize(try value(for: token), flag: token)
            case "--line":
                lineSegments.append(
                    try resolveNormalizedSegment(try value(for: token), flag: token))
            case "--line-color":
                lineColor = try resolveHexColor(try value(for: token), flag: token)
            case "--line-size":
                lineSize = try resolveAnnotationSize(try value(for: token), flag: token)
            case "--rectangle":
                rectangleRegions.append(
                    try resolveNormalizedRegion(try value(for: token), flag: token))
            case "--rectangle-color":
                rectangleColor = try resolveHexColor(try value(for: token), flag: token)
            case "--rectangle-size":
                rectangleSize = try resolveAnnotationSize(try value(for: token), flag: token)
            case "--highlighter":
                highlighterRegions.append(
                    try resolveNormalizedRegion(try value(for: token), flag: token))
            case "--highlighter-color":
                highlighterColor = try resolveHexColor(try value(for: token), flag: token)
            case "--blur-box":
                blurBoxRegions.append(
                    try resolveNormalizedRegion(try value(for: token), flag: token))
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
            case "--git-diff":
                if let gitDiffSource {
                    let message =
                        if case .staged = gitDiffSource {
                            "Cannot combine --git-diff with --git-staged."
                        } else {
                            "--git-diff may be provided only once."
                        }
                    throw CLIError.incompatibleOptions(message)
                }
                gitDiffSource = .revision(
                    try resolveGitDiffRange(try value(for: token), flag: token))
            case "--git-staged":
                if let gitDiffSource {
                    let message =
                        if case .revision = gitDiffSource {
                            "Cannot combine --git-staged with --git-diff."
                        } else {
                            "--git-staged may be provided only once."
                        }
                    throw CLIError.incompatibleOptions(message)
                }
                gitDiffSource = .staged
            case "--git-path":
                gitDiffPaths.append(try resolveGitPath(try value(for: token), flag: token))
            case "--git-context":
                gitDiffContextLines = try resolveGitContextLines(
                    try value(for: token), flag: token)
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
    }
}
