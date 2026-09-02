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
    var recipePath: String?
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
    var profile: ColorProfile?
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
    var showLanguageBadge: Bool?
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
    var seenOptionIDs: Set<CLIOptionID> = []

    init(_ arguments: [String]) throws {
        let remaining = ArraySlice(arguments)

        guard let command = remaining.first else { throw CLIError.helpRequested }
        if command == "--help" || command == "-h" { throw CLIError.helpRequested }

        guard let mode = CLIArgumentSchema.command(named: command) else {
            throw CLIError.unknownCommand(command)
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
            if token.hasPrefix("-") {
                guard let definition = CLIArgumentSchema.option(named: token) else {
                    throw CLIError.unknownFlag(token)
                }
                if mode == .terminalCapture, !definition.terminalCaptureAllowed {
                    throw CLIError.unknownFlag(token)
                }
                let rawValue = try parsedValue(for: definition, token: token)
                seenOptionIDs.insert(definition.id)
                try apply(definition.id, rawValue: rawValue, token: token)
            } else {
                // The first non-flag token is the input path; a second positional is
                // unexpected and rejected so a stray argument is not silently ignored.
                guard inputPath == nil else { throw CLIError.unknownFlag(token) }
                inputPath = token
            }
        }
    }

    private mutating func parsedValue(
        for definition: CLIOptionDefinition,
        token: String
    ) throws -> String? {
        switch definition.arity {
        case .flag: nil
        case .value: try value(for: token)
        }
    }

    private mutating func apply(
        _ option: CLIOptionID,
        rawValue: String?,
        token: String
    ) throws {
        // Value arity is enforced before dispatch from the schema. Keeping the local
        // fallback non-optional makes each resolver call concise without introducing a
        // second list of which cases consume values.
        let value = rawValue ?? ""
        switch option {
        case .help:
            throw CLIError.helpRequested
        case .out:
            outputPath = value
        case .image:
            imageInputPath = value
        case .quiet:
            quiet = true
        case .json:
            jsonOutput = true
        case .theme:
            themeID = try resolveTheme(value)
        case .language:
            languageID = try resolveLanguage(value)
        case .preset:
            presetID = try resolvePreset(value)
        case .presets:
            multiSizePresetIDs.formUnion(try resolvePresetList(value, flag: token))
        case .stylePreset:
            stylePresetID = try resolveStylePreset(value)
        case .recipe:
            recipePath = value
        case .canvasSize:
            canvasSize = try resolveCanvasSize(value, flag: token)
        case .scale:
            scale = try resolveScale(value, flag: token)
        case .font:
            fontName = try resolveFont(value)
        case .fontLigatures:
            fontLigatures = true
        case .noFontLigatures:
            fontLigatures = false
        case .fontSize:
            fontSize = try resolveFontSize(value, flag: token)
        case .padding:
            padding = try resolvePadding(value, flag: token)
        case .cornerRadius:
            cornerRadius = try resolveCornerRadius(value, flag: token)
        case .shadowRadius:
            shadowRadius = try resolveShadowRadius(value, flag: token)
        case .terminalWidth:
            terminalColumns = try resolveColumns(value, flag: token)
        case .wrapColumns:
            wrapColumns = try resolveWrapColumns(value, flag: token)
        case .formatCode:
            formatCode = true
        case .format:
            explicitFormat = try resolveFormat(value)
        case .profile:
            profile = try resolveProfile(value)
        case .transparent:
            transparent = true
        case .background:
            background = .gradient(try resolveBackground(value))
            gradientBackgroundRequested = true
        case .backgroundColor:
            background = .solid(try resolveBackgroundColor(value))
            solidBackgroundRequested = true
        case .backgroundGradient:
            customGradientColors = try resolveCustomGradientColors(value)
        case .backgroundAngle:
            customGradientAngle = try resolveBackgroundAngle(value)
        case .backgroundImage:
            backgroundImagePath = value
        case .backgroundFit:
            backgroundImageFit = try resolveBackgroundFit(value)
        case .backgroundBlur:
            backgroundImageBlur = try resolveBackgroundBlur(value, flag: token)
        case .backgroundDimming:
            backgroundImageDimming = try resolveBackgroundDimming(value, flag: token)
        case .watermark:
            watermarkText = try resolveWatermarkText(value)
        case .watermarkLogo:
            watermarkLogoPath = value
        case .watermarkColor:
            watermarkColor = try resolveWatermarkColor(value)
        case .watermarkPosition:
            watermarkPosition = try resolveWatermarkPosition(value)
        case .watermarkX:
            watermarkX = try resolveNormalizedCoordinate(value, flag: token)
        case .watermarkY:
            watermarkY = try resolveNormalizedCoordinate(value, flag: token)
        case .callout:
            calloutText = try resolveCalloutText(value)
        case .calloutX:
            calloutX = try resolveNormalizedCoordinate(value, flag: token)
        case .calloutY:
            calloutY = try resolveNormalizedCoordinate(value, flag: token)
        case .calloutColor:
            calloutColor = try resolveCalloutColor(value)
        case .calloutSize:
            calloutSize = try resolveCalloutSize(value)
        case .counter:
            counterNumber = try resolveCounterNumber(value)
        case .counterX:
            counterX = try resolveNormalizedCoordinate(value, flag: token)
        case .counterY:
            counterY = try resolveNormalizedCoordinate(value, flag: token)
        case .counterColor:
            counterColor = try resolveHexColor(value, flag: token)
        case .counterSize:
            counterSize = try resolveAnnotationSize(value, flag: token)
        case .arrow:
            arrowSegments.append(try resolveNormalizedSegment(value, flag: token))
        case .arrowColor:
            arrowColor = try resolveHexColor(value, flag: token)
        case .arrowSize:
            arrowSize = try resolveAnnotationSize(value, flag: token)
        case .line:
            lineSegments.append(try resolveNormalizedSegment(value, flag: token))
        case .lineColor:
            lineColor = try resolveHexColor(value, flag: token)
        case .lineSize:
            lineSize = try resolveAnnotationSize(value, flag: token)
        case .rectangle:
            rectangleRegions.append(try resolveNormalizedRegion(value, flag: token))
        case .rectangleColor:
            rectangleColor = try resolveHexColor(value, flag: token)
        case .rectangleSize:
            rectangleSize = try resolveAnnotationSize(value, flag: token)
        case .highlighter:
            highlighterRegions.append(try resolveNormalizedRegion(value, flag: token))
        case .highlighterColor:
            highlighterColor = try resolveHexColor(value, flag: token)
        case .blurBox:
            blurBoxRegions.append(try resolveNormalizedRegion(value, flag: token))
        case .frame:
            imageFrame = try resolveImageFrame(value)
        case .frameAppearance:
            frameAppearance = try resolveFrameAppearance(value)
        case .noOverwrite:
            noOverwrite = true
        case .windowTitle:
            windowTitle = value
        case .filename:
            metadataFilename = value
        case .stdinName:
            stdinFilename = value
        case .title:
            metadataTitle = value
        case .caption:
            metadataCaption = value
        case .languageBadge:
            showLanguageBadge = true
        case .noLanguageBadge:
            showLanguageBadge = false
        case .lineNumbers:
            showLineNumbers = true
        case .noLineNumbers:
            showLineNumbers = false
        case .chrome:
            showChrome = token == "--chrome"
        case .shadow:
            showShadow = token == "--shadow"
        case .highlightLines:
            highlightedLineRanges = try resolveLineRanges(value, flag: token)
        case .redactLines:
            redactedLineRanges = try resolveLineRanges(value, flag: token)
        case .redactSecrets:
            redactSecrets = true
        case .focusLines:
            focusHighlightedLines = token == "--focus-lines"
        case .diffBands:
            diffDecorations = token == "--diff-bands"
        case .recursive:
            recursiveBatch = true
        case .failOnSkipped:
            failOnSkipped = true
        case .failOnEmpty:
            failOnEmpty = true
        case .skippedReport:
            skippedReportPath = value
        case .manifest:
            batchManifestPath = value
        case .dryRun:
            dryRunBatch = true
        case .includeExt:
            batchIncludeExtensions.formUnion(try resolveExtensionList(value, flag: token))
        case .excludeExt:
            batchExcludeExtensions.formUnion(try resolveExtensionList(value, flag: token))
        case .stdin:
            readStdin = true
        case .gitDiff:
            if let gitDiffSource {
                let message =
                    if case .staged = gitDiffSource {
                        "Cannot combine --git-diff with --git-staged."
                    } else {
                        "--git-diff may be provided only once."
                    }
                throw CLIError.incompatibleOptions(message)
            }
            gitDiffSource = .revision(try resolveGitDiffRange(value, flag: token))
        case .gitStaged:
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
        case .gitPath:
            gitDiffPaths.append(try resolveGitPath(value, flag: token))
        case .gitContext:
            gitDiffContextLines = try resolveGitContextLines(value, flag: token)
        case .copy:
            copyToClipboard = true
        case .edit:
            openInEditor = true
        case .textSidecar:
            textSidecar = true
        case .markdownSidecar:
            markdownSidecar = true
        case .htmlSidecar:
            htmlSidecar = true
        case .sidecars:
            let sidecars = try resolveSidecars(value, flag: token)
            textSidecar = textSidecar || sidecars.text
            markdownSidecar = markdownSidecar || sidecars.markdown
            htmlSidecar = htmlSidecar || sidecars.html
        }
    }
}
