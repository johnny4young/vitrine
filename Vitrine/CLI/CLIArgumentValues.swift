import Foundation

extension CLIArgumentParser {
    // MARK: - Value resolution (each rejects an unknown id with a clear error)

    /// Accepts one Git revision or range while rejecting values Git could interpret
    /// as command options. The value remains one `Process` argument; no shell parses it.
    func resolveGitDiffRange(_ raw: String, flag: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("-"), !containsControlCharacter(raw) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Validates a repeatable Git pathspec. A leading dash is intentionally valid:
    /// the executor places pathspecs after `--`, where Git cannot treat them as flags.
    func resolveGitPath(_ raw: String, flag: String) throws -> String {
        guard !raw.isEmpty, !containsControlCharacter(raw) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return raw
    }

    func resolveGitContextLines(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw), GitDiffInputLoader.contextLinesRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Validates a theme id against the built-in catalog so a typo fails up front
    /// rather than silently falling back to One Dark at render time.
    func resolveTheme(_ raw: String) throws -> String {
        guard Theme.builtInIDs.contains(raw) else {
            throw CLIError.invalidValue(flag: "--theme", value: raw)
        }
        return raw
    }

    /// Validates a language id against the advertised catalog.
    func resolveLanguage(_ raw: String) throws -> String {
        guard Language(rawValue: raw) != nil else {
            throw CLIError.invalidValue(flag: "--language", value: raw)
        }
        return raw
    }

    /// Validates a destination-preset id against the catalog.
    func resolvePreset(_ raw: String) throws -> String {
        guard ExportPreset.preset(withID: raw) != nil else {
            throw CLIError.invalidValue(flag: "--preset", value: raw)
        }
        return raw
    }

    /// Parses a comma-separated destination preset selection for `multi-size`.
    /// `all` is accepted as the complete catalog; every other id is validated now so
    /// a typo fails before the output directory or any artifact is created.
    func resolvePresetList(_ raw: String, flag: String) throws -> Set<String> {
        let ids =
            raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !ids.isEmpty, !ids.contains(where: \.isEmpty) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        if ids == ["all"] { return Set(ExportPreset.all.map(\.id)) }
        guard !ids.contains("all"), ids.allSatisfy({ ExportPreset.preset(withID: $0) != nil })
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return Set(ids)
    }

    /// Validates an immutable built-in style preset. User presets are intentionally
    /// excluded so scripts render identically on every machine.
    func resolveStylePreset(_ raw: String) throws -> String {
        guard StylePreset.builtInIDs.contains(raw) else {
            throw CLIError.invalidValue(flag: "--style-preset", value: raw)
        }
        return raw
    }

    /// Parses an exact logical WIDTHxHEIGHT canvas within the renderer's bounded
    /// automation range. `--scale` multiplies these values into final pixels.
    func resolveCanvasSize(_ raw: String, flag: String) throws -> CGSize {
        let components = raw.split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "x" || $0 == "X" })
        guard components.count == 2,
            let width = Int(components[0].trimmingCharacters(in: .whitespaces)),
            let height = Int(components[1].trimmingCharacters(in: .whitespaces)),
            CLIOptions.canvasDimensionRange.contains(width),
            CLIOptions.canvasDimensionRange.contains(height)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return CGSize(width: width, height: height)
    }

    /// Validates a code font family against the same catalog exposed in the editor.
    func resolveFont(_ raw: String) throws -> String {
        guard CodeFont.all.contains(raw) else {
            throw CLIError.invalidValue(flag: "--font", value: raw)
        }
        return raw
    }

    /// Validates a gradient id against the same built-in catalog exposed by
    /// `vitrine list backgrounds`.
    func resolveBackground(_ raw: String) throws -> GradientPreset {
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
    func resolveBackgroundColor(_ raw: String) throws -> RGBAColor {
        guard let color = RGBAColor(hex: raw) else {
            throw CLIError.invalidValue(flag: "--background-color", value: raw)
        }
        return color
    }

    /// Parses at least two comma-separated RGB/RGBA colors for a custom gradient.
    func resolveCustomGradientColors(_ raw: String) throws -> [RGBAColor] {
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
    func resolveBackgroundAngle(_ raw: String) throws -> Double {
        guard let angle = Double(raw), angle.isFinite, (0...360).contains(angle) else {
            throw CLIError.invalidValue(flag: "--background-angle", value: raw)
        }
        return angle
    }

    /// Spreads CLI colors evenly across the gradient axis, matching preset conversion.
    func makeCustomGradient(colors: [RGBAColor], angle: Double?) -> CustomGradient {
        let lastIndex = Double(colors.count - 1)
        let stops = colors.enumerated().map { index, color in
            GradientStop(color: color, location: Double(index) / lastIndex)
        }
        return CustomGradient(stops: stops, angle: angle ?? CustomGradient.default.angle)
    }

    /// Resolves the app's stable local image-background sizing behavior.
    func resolveBackgroundFit(_ raw: String) throws -> BackgroundFit {
        guard let fit = BackgroundFit(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--background-fit", value: raw)
        }
        return fit
    }

    /// Parses the image-background blur range exposed by the editor.
    func resolveBackgroundBlur(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, ImageBackground.blurRange.contains(value)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses the normalized image-background dimming range exposed by the editor.
    func resolveBackgroundDimming(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, ImageBackground.dimmingRange.contains(value)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Normalizes the text in the same way as Brand Kit fields and rejects a blank
    /// badge so a successful command can never silently render no watermark.
    func resolveWatermarkText(_ raw: String) throws -> String {
        try resolveVisibleText(raw, flag: "--watermark")
    }

    /// Parses a CSS-style RGB/RGBA hex tint for the watermark text.
    func resolveWatermarkColor(_ raw: String) throws -> RGBAColor {
        try resolveHexColor(raw, flag: "--watermark-color")
    }

    /// Resolves one of the stable corner ids advertised by the watermark-position catalog.
    func resolveWatermarkPosition(
        _ raw: String
    ) throws -> CLIOptions.WatermarkPosition {
        guard let position = CLIOptions.WatermarkPosition(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--watermark-position", value: raw)
        }
        return position
    }

    /// Parses a normalized canvas coordinate for deterministic free watermark placement.
    func resolveNormalizedCoordinate(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), value.isFinite, (0...1).contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Normalizes callout copy and rejects blank content that would render no mark.
    func resolveCalloutText(_ raw: String) throws -> String {
        try resolveVisibleText(raw, flag: "--callout")
    }

    /// Trims user-facing badge copy and rejects values that cannot produce pixels.
    func resolveVisibleText(_ raw: String, flag: String) throws -> String {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return normalized
    }

    /// Parses the same fixed-sRGB hex color accepted by the annotation toolbar model.
    func resolveCalloutColor(_ raw: String) throws -> RGBAColor {
        try resolveHexColor(raw, flag: "--callout-color")
    }

    /// Parses a CSS-style fixed-sRGB color for any CLI overlay control.
    func resolveHexColor(_ raw: String, flag: String) throws -> RGBAColor {
        guard let color = RGBAColor(hex: raw) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return color
    }

    /// Parses the editor annotation toolbar's supported size-weight range.
    func resolveCalloutSize(_ raw: String) throws -> Double {
        try resolveAnnotationSize(raw, flag: "--callout-size")
    }

    /// Parses an annotation size using the editor toolbar's shared bounds.
    func resolveAnnotationSize(_ raw: String, flag: String) throws -> Double {
        guard let size = Double(raw), size.isFinite, Annotation.thicknessRange.contains(size) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return size
    }

    /// Parses a compact positive counter label that remains legible in the badge.
    func resolveCounterNumber(_ raw: String) throws -> Int {
        guard let number = Int(raw), CLIOptions.counterNumberRange.contains(number) else {
            throw CLIError.invalidValue(flag: "--counter", value: raw)
        }
        return number
    }

    /// Parses two normalized endpoints and rejects invisible zero-length marks.
    func resolveNormalizedSegment(
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

    /// Parses opposite region corners and rejects collapsed width or height.
    func resolveNormalizedRegion(
        _ raw: String, flag: String
    ) throws -> (start: CGPoint, end: CGPoint) {
        let segment = try resolveNormalizedSegment(raw, flag: flag)
        guard segment.start.x != segment.end.x, segment.start.y != segment.end.y else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return segment
    }

    /// Resolves a stable image-frame id advertised by `vitrine list frames`.
    func resolveImageFrame(_ raw: String) throws -> CLIOptions.ImageFrameOption {
        guard let frame = CLIOptions.ImageFrameOption(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--frame", value: raw)
        }
        return frame
    }

    /// Resolves a stable frame-appearance id advertised by the CLI catalog.
    func resolveFrameAppearance(
        _ raw: String
    ) throws -> CLIOptions.ImageFrameAppearance {
        guard let appearance = CLIOptions.ImageFrameAppearance(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--frame-appearance", value: raw)
        }
        return appearance
    }

    /// Parses and range-checks the export scale (1...3).
    func resolveScale(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw),
            SettingsDefaults.exportScaleRange.contains(value)
        else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the code font size in points (Style pane bounds).
    func resolveFontSize(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.fontSizeRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the canvas padding in points (Style pane bounds).
    func resolvePadding(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.paddingRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the code-card corner radius in points.
    func resolveCornerRadius(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.cornerRadiusRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the drop-shadow blur radius in points.
    func resolveShadowRadius(_ raw: String, flag: String) throws -> Double {
        guard let value = Double(raw), SettingsDefaults.shadowRadiusRange.contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses a strict, 1-based line range list (for example `3,7-9,12`). Unlike the
    /// editor's forgiving text field, the CLI rejects malformed fragments so automation
    /// cannot silently render the wrong emphasized rows.
    func resolveLineRanges(
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

    func positiveLine(_ text: Substring) -> Int? {
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
    func resolveColumns(_ raw: String, flag: String) throws -> Int {
        guard let value = Int(raw), (1...1000).contains(value) else {
            throw CLIError.invalidValue(flag: flag, value: raw)
        }
        return value
    }

    /// Parses and range-checks the editor's code soft-wrap width. Uses the same
    /// bounds as the Style pane, so a CLI render and a saved editor config agree.
    func resolveWrapColumns(_ raw: String, flag: String) throws -> Int {
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
    func resolveFormat(
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

    /// Parses the output format (`png`/`pdf`/`heic`/`avif`).
    func resolveFormat(_ raw: String) throws -> ExportFormat {
        guard let format = ExportFormat(rawValue: raw.lowercased()) else {
            throw CLIError.invalidValue(flag: "--format", value: raw)
        }
        return format
    }

    /// Parses the color profile, accepting the documented spellings `srgb` and `p3`
    /// in addition to the raw enum names.
    func resolveProfile(_ raw: String) throws -> ColorProfile {
        switch raw.lowercased() {
        case "srgb", "srgb-iec61966-2.1": return .sRGB
        case "p3", "displayp3", "display-p3": return .displayP3
        default: throw CLIError.invalidValue(flag: "--profile", value: raw)
        }
    }

    /// Parses a comma-separated batch extension list, accepting either `swift` or
    /// `.swift` spellings and normalizing everything to lowercase without the dot.
    func resolveExtensionList(_ raw: String, flag: String) throws -> Set<String> {
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
    func resolveSidecars(
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
