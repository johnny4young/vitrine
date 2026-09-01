import Foundation

extension CLIArgumentParser {
    /// Validates option combinations and materializes the immutable command contract.
    mutating func resolvedOptions() throws -> CLIOptions {
        let recipe = try recipePath.map(CLIRecipeLoader.load(path:))
        try validateOptionCombinations(recipe: recipe)
        return try materializeOptions(recipe: recipe)
    }

    /// Keeps the compatibility matrix separate from immutable option construction.
    /// Besides making each responsibility reviewable, this bounds the stack frame
    /// the Swift backend must instrument in sanitizer builds.
    private mutating func validateOptionCombinations(recipe: WorkspaceRecipe?) throws {
        if mode == .terminalCapture, !copyToClipboard, !openInEditor {
            throw CLIError.missingRequired("--copy or --edit")
        }

        // Alternate source controls, image-input controls, `--copy`, and `--edit` are
        // render/multi-size-only (a batch needs a real input folder).
        if mode == .batch,
            readStdin || gitDiffSource != nil || !gitDiffPaths.isEmpty
                || gitDiffContextLines != nil || imageInputPath != nil
                || stdinFilename != nil || copyToClipboard
                || openInEditor || imageFrame != nil || frameAppearance != nil
        {
            let flag: String
            if readStdin {
                flag = "--stdin"
            } else if let gitDiffSource {
                flag = if case .staged = gitDiffSource { "--git-staged" } else { "--git-diff" }
            } else if !gitDiffPaths.isEmpty {
                flag = "--git-path"
            } else if gitDiffContextLines != nil {
                flag = "--git-context"
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
        if !gitDiffPaths.isEmpty, gitDiffSource == nil {
            throw CLIError.incompatibleOptions("--git-path requires --git-diff or --git-staged.")
        }
        if gitDiffContextLines != nil, gitDiffSource == nil {
            throw CLIError.incompatibleOptions(
                "--git-context requires --git-diff or --git-staged.")
        }
        try CLIArgumentSchema.validateAvailability(
            command: mode, seen: seenOptionIDs, group: .multiSizeOnly)
        if mode == .multiSize {
            if presetID != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot combine multi-size with --preset; use --presets.")
            }
            if recipe?.output.destinationPresetID != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot use a recipe destination preset with multi-size; use --presets."
                )
            }
            if canvasSize != nil || scale != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot combine multi-size with --canvas-size or --scale; destination presets pin their dimensions."
                )
            }
            if recipe?.output.canvasSize != nil || recipe?.output.scale != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot use recipe canvas-size or scale defaults with multi-size; destination presets pin their dimensions."
                )
            }
            if imageInputPath != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot combine multi-size with --image; use a code or stdin source.")
            }
            if copyToClipboard || openInEditor {
                throw CLIError.incompatibleOptions(
                    "Cannot combine multi-size with --copy or --edit.")
            }
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
        if arrowSegments.isEmpty, arrowColor != nil || arrowSize != nil {
            throw CLIError.incompatibleOptions(
                "--arrow-color and --arrow-size require --arrow.")
        }
        if lineSegments.isEmpty, lineColor != nil || lineSize != nil {
            throw CLIError.incompatibleOptions(
                "--line-color and --line-size require --line.")
        }
        if rectangleRegions.isEmpty, rectangleColor != nil || rectangleSize != nil {
            throw CLIError.incompatibleOptions(
                "--rectangle-color and --rectangle-size require --rectangle.")
        }
        if highlighterRegions.isEmpty, highlighterColor != nil {
            throw CLIError.incompatibleOptions("--highlighter-color requires --highlighter.")
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
        if gitDiffSource != nil, let inputPath {
            throw CLIError.incompatibleOptions(
                "Cannot combine a Git diff source with input file \"\(inputPath)\".")
        }
        if gitDiffSource != nil, readStdin {
            throw CLIError.incompatibleOptions("Cannot combine a Git diff source with --stdin.")
        }
        if gitDiffSource != nil, imageInputPath != nil {
            throw CLIError.incompatibleOptions("Cannot combine a Git diff source with --image.")
        }
        if gitDiffSource != nil, diffDecorations == nil {
            diffDecorations = true
        }
        try CLIArgumentSchema.validateAvailability(
            command: mode, seen: seenOptionIDs, group: .batchOnly)
        let recipeHeaderRequested =
            recipe?.metadata.windowTitle != nil || recipe?.metadata.header.isEmpty == false
        let metadataHeaderRequested =
            recipeHeaderRequested || windowTitle != nil || metadataFilename != nil
            || metadataTitle != nil || metadataCaption != nil || showLanguageBadge != nil
        let styleOptionsRequested =
            recipe != nil || stylePresetID != nil || canvasSize != nil || background != nil
            || backgroundImagePath != nil || transparent || fontName != nil
            || fontLigatures != nil
            || fontSize != nil || padding != nil
            || cornerRadius != nil || shadowRadius != nil || wrapColumns != nil
            || formatCode
            || watermarkContentRequested
            || calloutText != nil
            || counterNumber != nil
            || !arrowSegments.isEmpty
            || !lineSegments.isEmpty
            || !rectangleRegions.isEmpty
            || !highlighterRegions.isEmpty
            || !blurBoxRegions.isEmpty
            || showLineNumbers != nil || showChrome != nil || showShadow != nil
            || highlightedLineRanges != nil || redactedLineRanges != nil
            || redactSecrets || focusHighlightedLines != nil || diffDecorations != nil

        if imageInputPath != nil {
            if recipe != nil {
                throw CLIError.incompatibleOptions(
                    "Cannot combine --image with --recipe; workspace recipes configure code captures."
                )
            }
            if openInEditor {
                throw CLIError.incompatibleOptions("Cannot combine --image with --edit.")
            }
            let codeOnlyOptionsRequested =
                themeID != nil || languageID != nil || fontName != nil || fontLigatures != nil
                || fontSize != nil || terminalColumns != nil || wrapColumns != nil || formatCode
                || metadataFilename != nil || metadataTitle != nil
                || metadataCaption != nil || showLanguageBadge != nil || showLineNumbers != nil
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
    }

    /// Resolves recipe fallbacks and constructs the value returned to the renderer.
    /// All invalid combinations have already been rejected by the validation pass.
    private func materializeOptions(recipe: WorkspaceRecipe?) throws -> CLIOptions {
        let resolvedPresetID = presetID ?? recipe?.output.destinationPresetID
        let resolvedCanvasSize = canvasSize ?? recipe?.output.canvasSize?.cgSize
        let resolvedScale = scale ?? recipe?.output.scale
        let resolvedProfile = profile ?? recipe?.output.colorProfile ?? .fallback
        let resolvedLanguageBadge =
            showLanguageBadge ?? recipe?.metadata.header.showLanguageBadge ?? false

        // Input is a code file, local image, stdin, or a generated local Git diff;
        // output is required unless copying or handing the source to the editor.
        let resolvedInput: String
        if let imageInputPath {
            resolvedInput = imageInputPath
        } else if readStdin || gitDiffSource != nil {
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
                    mode == .render ? "--out output path" : "--out output folder")
            }
            resolvedOutput = outputPath
        }

        let resolvedFormat = try resolveFormat(
            explicitFormat, fallback: recipe?.output.format, command: mode,
            outputPath: resolvedOutput)
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
        let arrows = arrowSegments.map {
            CLIOptions.SegmentAnnotation(
                start: $0.start, end: $0.end, color: arrowColor, size: arrowSize)
        }
        let lines = lineSegments.map {
            CLIOptions.SegmentAnnotation(
                start: $0.start, end: $0.end, color: lineColor, size: lineSize)
        }
        let rectangles = rectangleRegions.map {
            CLIOptions.SegmentAnnotation(
                start: $0.start, end: $0.end, color: rectangleColor, size: rectangleSize)
        }
        let highlighters = highlighterRegions.map {
            CLIOptions.SegmentAnnotation(
                start: $0.start, end: $0.end, color: highlighterColor, size: nil)
        }
        let blurBoxes = blurBoxRegions.map {
            CLIOptions.SegmentAnnotation(
                start: $0.start, end: $0.end, color: nil, size: nil)
        }
        let resolvedMultiSizePresetIDs =
            mode == .multiSize
            ? ExportPreset.all.filter {
                multiSizePresetIDs.isEmpty || multiSizePresetIDs.contains($0.id)
            }.map(\.id)
            : []

        return CLIOptions(
            command: mode,
            quiet: quiet,
            jsonOutput: jsonOutput,
            inputKind: imageInputPath == nil ? .code : .image,
            inputPath: resolvedInput,
            outputPath: resolvedOutput,
            themeID: themeID,
            language:
                mode == .terminalCapture
                ? .terminal : languageID.flatMap(Language.init(rawValue:)),
            presetID: resolvedPresetID,
            multiSizePresetIDs: resolvedMultiSizePresetIDs,
            stylePresetID: stylePresetID,
            recipe: recipe,
            canvasSize: resolvedCanvasSize,
            scale: resolvedScale,
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
            profile: resolvedProfile,
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
            arrows: arrows,
            lines: lines,
            rectangles: rectangles,
            highlighters: highlighters,
            blurBoxes: blurBoxes,
            imageFrame: imageFrame,
            frameAppearance: frameAppearance,
            noOverwrite: noOverwrite,
            windowTitle: windowTitle,
            metadataFilename: metadataFilename,
            stdinFilename: stdinFilename,
            metadataTitle: metadataTitle,
            metadataCaption: metadataCaption,
            showLanguageBadge: resolvedLanguageBadge,
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
            gitDiffSource: gitDiffSource,
            gitDiffPaths: gitDiffPaths,
            gitDiffContextLines: gitDiffContextLines ?? GitDiffInputLoader.defaultContextLines,
            readStdin: readStdin,
            copyToClipboard: copyToClipboard,
            openInEditor: openInEditor,
            textSidecar: textSidecar,
            markdownSidecar: markdownSidecar,
            htmlSidecar: htmlSidecar
        )
    }
}
