import Foundation
import VitrineDomain
import VitrineRendering

/// Maps an editor window's render state to the `vitrine render` line that reproduces it, or
/// names what the line can't include. Source text never reaches the line: the input is a
/// placeholder file, and redaction travels as line numbers plus a secret scan.
struct CLIReproductionCommand {
    /// A part of the image this builder can't put on a safe, faithful line.
    enum Limit: CaseIterable, Equatable {
        case annotations, pastedImage, imageBackground, customTheme, customGradient, brandMark
        case controlCharacters, likelySecret, recipeOutsideWorkspace
    }

    enum Outcome: Equatable {
        case command(String)
        case unavailable([Limit])
    }

    /// `relativePath` is from the association's workspace, or `nil` when the recipe sits
    /// outside it: the line never carries an absolute path.
    struct RecipeFile {
        var relativePath: String?
        var recipe: WorkspaceRecipe
    }

    var style: SnapshotConfig
    var destinationPresetID: String?
    var scale: Int
    var format: ExportFormat
    var profile: ColorProfile
    var watermark: Watermark?

    /// A referenced recipe wins when it can express the state, because it also carries
    /// custom themes and gradients. Otherwise the line falls back to plain flags.
    func outcome(recipe: RecipeFile? = nil) -> Outcome {
        var plan = plan(recipeFile: nil)
        var limits = Set(plan.limits)
        if let recipe, canOverride(recipe.recipe) {
            let viaRecipe = self.plan(recipeFile: recipe)
            if viaRecipe.limits.isEmpty, recipe.relativePath != nil {
                plan = viaRecipe
                limits = []
            } else if viaRecipe.limits.isEmpty, !limits.isEmpty {
                limits = [.recipeOutsideWorkspace]
            }
        }
        limits.formUnion(contentLimits)
        limits.formUnion(argumentLimits(plan.arguments))
        guard limits.isEmpty else { return .unavailable(Limit.allCases.filter(limits.contains)) }
        return .command(Self.line(["vitrine"] + plan.arguments))
    }

    static func line(_ arguments: [String]) -> String {
        arguments.map(shellQuoted).joined(separator: " ")
    }

    /// Quotes one argument for POSIX shells, zsh and fish. A leading `=` or `~` expands in
    /// zsh, so only inert characters stay bare. Fish reads `\'` as an escape inside single
    /// quotes, so backslashes and quotes are always written outside them.
    static func shellQuoted(_ argument: String) -> String {
        let isInert = argument.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || "_@%+:,./-".contains($0))
        }
        if isInert, !argument.isEmpty { return argument }
        var quoted = ""
        var isOpen = false
        for character in argument {
            let isEscaped = character == "'" || character == "\\"
            if isEscaped == isOpen {
                quoted += "'"
                isOpen.toggle()
            }
            if isEscaped { quoted += "\\" }
            quoted.append(character)
        }
        if isOpen { quoted += "'" }
        return quoted.isEmpty ? "''" : quoted
    }

    private var contentLimits: Set<Limit> {
        var limits: Set<Limit> = []
        if !style.annotations.isEmpty { limits.insert(.annotations) }
        if style.usesImageContent { limits.insert(.pastedImage) }
        if case .image = style.background { limits.insert(.imageBackground) }
        if let watermark,
            watermark.logoImageData != nil || watermark.qrImage != nil
                || watermark.qrIdentity != nil || watermark.placement == .footerBar
        {
            limits.insert(.brandMark)
        }
        return limits
    }

    /// Terminal control sequences survive quoting, and header text can hold a pasted token.
    private func argumentLimits(_ arguments: [String]) -> Set<Limit> {
        var limits: Set<Limit> = []
        let isControl: (Unicode.Scalar) -> Bool = {
            $0 != "\n" && $0 != "\t" && ($0.value < 0x20 || (0x7F...0x9F).contains($0.value))
        }
        if arguments.contains(where: { $0.unicodeScalars.contains(where: isControl) }) {
            limits.insert(.controlCharacters)
        }
        let scanned: Set = ["--window-title", "--title", "--caption", "--filename", "--watermark"]
        for (flag, value) in zip(arguments, arguments.dropFirst()) where scanned.contains(flag) {
            if !SecretScanner.secretLines(in: value).isEmpty { limits.insert(.likelySecret) }
        }
        return limits
    }

    private struct Plan {
        var arguments: [String]
        var limits: [Limit] = []
    }

    private func baseline(_ recipe: WorkspaceRecipe?) -> SnapshotConfig {
        var base = SnapshotConfig().styled(
            presetID: destinationPresetID, themeID: nil, transparent: false)
        if let recipe {
            recipe.style.apply(to: &base, resolvingThemeWith: recipe.theme(withID:))
            base.windowTitle = recipe.metadata.windowTitle ?? base.windowTitle
        }
        return base
    }

    /// False when the recipe sets a value that no flag can clear.
    private func canOverride(_ recipe: WorkspaceRecipe) -> Bool {
        let base = baseline(recipe)
        let header = recipe.metadata.header
        let target = style.metadata
        return recipe.output.canvasSize == nil
            && (recipe.output.destinationPresetID == nil || destinationPresetID != nil)
            && (base.wrapColumns == nil || style.wrapColumns != nil)
            && (base.windowTitle.isEmpty || !style.windowTitle.isEmpty)
            && (header.filename == nil || target.filename != nil)
            && (header.title == nil || target.title != nil)
            && (header.caption == nil || target.caption != nil)
    }

    /// Emits only what differs from the baseline, in the CLI's precedence order.
    private func plan(recipeFile: RecipeFile?) -> Plan {
        let recipe = recipeFile?.recipe
        let base = baseline(recipe)
        var plan = Plan(arguments: ["render"] + inputArguments)
        if let path = recipeFile?.relativePath { plan.arguments += ["--recipe", path] }
        if let destinationPresetID, destinationPresetID != recipe?.output.destinationPresetID {
            plan.arguments += ["--preset", destinationPresetID]
        }
        let preset = ExportPreset.preset(withID: destinationPresetID)
        if scale != recipe?.output.scale ?? preset?.scale ?? SettingsDefaults.exportScale {
            plan.arguments += ["--scale", String(scale)]
        }
        if profile != recipe?.output.colorProfile ?? .fallback {
            plan.arguments += ["--profile", profile == .displayP3 ? "p3" : "srgb"]
        }
        if style.theme != base.theme {
            if Theme.builtInIDs.contains(style.theme.id) {
                plan.arguments += ["--theme", style.theme.id]
            } else {
                plan.limits.append(.customTheme)
            }
        }
        plan.arguments += styleFlags(over: base, header: recipe?.metadata.header ?? .init())
        if style.background != base.background {
            if let flags = backgroundFlags {
                plan.arguments += flags
            } else {
                plan.limits.append(.customGradient)
            }
        }
        plan.arguments += watermarkFlags
        return plan
    }

    /// The file the line renders. It stands in for the user's own.
    var inputPlaceholder: String { "input.\(style.language.fileExtension ?? "txt")" }

    /// The placeholder's extension selects the language where one exists.
    private var inputArguments: [String] {
        let arguments = [inputPlaceholder, "--out", "image.\(format.fileExtension)"]
        return style.language.fileExtension == nil
            ? arguments + ["--language", style.language.rawValue] : arguments
    }

    private func styleFlags(over base: SnapshotConfig, header: SnapshotMetadata) -> [String] {
        var flags: [String] = []
        func toggle(_ on: String, _ off: String, _ value: Bool, _ baseValue: Bool) {
            if value != baseValue { flags.append(value ? on : off) }
        }
        func label(_ flag: String, _ value: String?, _ baseValue: String?) {
            if value != baseValue, let value { flags += [flag, value] }
        }
        let target = style.metadata
        label("--font", style.fontName, base.fontName)
        label("--font-size", text(style.fontSize), text(base.fontSize))
        toggle("--font-ligatures", "--no-font-ligatures", style.fontLigatures, base.fontLigatures)
        label("--padding", text(style.padding), text(base.padding))
        label("--padding-mode", style.paddingMode.rawValue, base.paddingMode.rawValue)
        label("--corner-radius", text(style.cornerRadius), text(base.cornerRadius))
        toggle("--shadow", "--no-shadow", style.showShadow, base.showShadow)
        label("--shadow-radius", text(style.shadowRadius), text(base.shadowRadius))
        toggle("--chrome", "--no-chrome", style.showChrome, base.showChrome)
        toggle("--line-numbers", "--no-line-numbers", style.showLineNumbers, base.showLineNumbers)
        label(
            "--wrap-columns", style.wrapColumns.map(String.init), base.wrapColumns.map(String.init))
        label("--window-title", style.windowTitle, base.windowTitle)
        // Only the leaf travels, so a path typed into the header stays out of the line.
        let leaf = target.filename?.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
        label("--filename", leaf.map(String.init), header.filename)
        label("--title", target.title, header.title)
        label("--caption", target.caption, header.caption)
        toggle(
            "--language-badge", "--no-language-badge", target.showLanguageBadge,
            header.showLanguageBadge)
        label("--highlight-lines", lineSpec(style.highlightedLineRanges), "")
        label("--redact-lines", lineSpec(style.redactedLineRanges), "")
        // Line numbers fail open on a different file, so the scan runs as well.
        if !style.redactedLineRanges.isEmpty { flags.append("--redact-secrets") }
        toggle("--focus-lines", "--no-focus-lines", style.focusHighlightedLines, false)
        toggle("--diff-bands", "--no-diff-bands", style.diffDecorations, false)
        label("--terminal-width", style.terminalColumns.map(String.init), nil)
        if style.language == .terminal {
            label(
                "--terminal-palette", style.terminalPalette.rawValue, base.terminalPalette.rawValue)
            label("--terminal-cursor", style.terminalCursor.rawValue, base.terminalCursor.rawValue)
        }
        return flags
    }

    /// `nil` when no flag says it: the CLI spreads gradient stops evenly.
    private var backgroundFlags: [String]? {
        switch style.background {
        case .solid(let color): return ["--background-color", color.hexString]
        case .gradient(let preset): return ["--background", preset.rawValue.lowercased()]
        case .transparent: return ["--transparent"]
        case .image: return []
        case .customGradient(let gradient):
            let lastIndex = Double(gradient.stops.count - 1)
            let evenStops = gradient.stops.enumerated().map { index, stop in
                GradientStop(color: stop.color, location: Double(index) / lastIndex)
            }
            guard CustomGradient(stops: evenStops, angle: gradient.angle) == gradient else {
                return nil
            }
            let colors = gradient.stops.map(\.color.hexString).joined(separator: ",")
            return ["--background-gradient", colors, "--background-angle", text(gradient.angle)]
        }
    }

    private var watermarkFlags: [String] {
        guard let watermark, !watermark.text.isEmpty else { return [] }
        var flags = ["--watermark", watermark.text]
        if let tint = watermark.tint { flags += ["--watermark-color", tint.hexString] }
        let positions: [Watermark.Placement: String] = [
            .bottomLeading: "bottom-left", .topTrailing: "top-right", .topLeading: "top-left",
            .free: "free",
        ]
        if let position = positions[watermark.placement] {
            flags += ["--watermark-position", position]
        }
        if watermark.placement == .free {
            let center = watermark.freePosition
            flags += ["--watermark-x", text(center.x), "--watermark-y", text(center.y)]
        }
        return flags
    }

    private func lineSpec(_ ranges: [ClosedRange<Int>]) -> String {
        LineHighlight.describe(ranges).replacingOccurrences(of: " ", with: "")
    }

    private func text(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
