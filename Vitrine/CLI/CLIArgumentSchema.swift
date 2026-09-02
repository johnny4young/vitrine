import Foundation

/// Stable identity for every public render option. Parsing, value arity, aliases,
/// constrained-command availability, semantic mode checks, and help all consume the
/// same definitions below so adding a flag cannot update only one surface.
nonisolated enum CLIOptionID: String, CaseIterable, Hashable, Sendable {
    case out
    case quiet
    case json
    case copy
    case edit
    case stdin
    case gitDiff
    case gitStaged
    case gitPath
    case gitContext
    case image
    case frame
    case frameAppearance
    case stdinName
    case theme
    case language
    case preset
    case presets
    case stylePreset
    case recipe
    case canvasSize
    case scale
    case font
    case fontLigatures
    case noFontLigatures
    case fontSize
    case padding
    case cornerRadius
    case shadowRadius
    case terminalWidth
    case wrapColumns
    case formatCode
    case format
    case profile
    case transparent
    case background
    case backgroundColor
    case backgroundGradient
    case backgroundAngle
    case backgroundImage
    case backgroundFit
    case backgroundBlur
    case backgroundDimming
    case watermark
    case watermarkLogo
    case watermarkColor
    case watermarkPosition
    case watermarkX
    case watermarkY
    case callout
    case calloutX
    case calloutY
    case calloutColor
    case calloutSize
    case counter
    case counterX
    case counterY
    case counterColor
    case counterSize
    case arrow
    case arrowColor
    case arrowSize
    case line
    case lineColor
    case lineSize
    case rectangle
    case rectangleColor
    case rectangleSize
    case highlighter
    case highlighterColor
    case blurBox
    case noOverwrite
    case windowTitle
    case filename
    case title
    case caption
    case languageBadge
    case noLanguageBadge
    case lineNumbers
    case noLineNumbers
    case chrome
    case shadow
    case highlightLines
    case redactLines
    case redactSecrets
    case focusLines
    case diffBands
    case recursive
    case failOnSkipped
    case failOnEmpty
    case skippedReport
    case manifest
    case dryRun
    case includeExt
    case excludeExt
    case textSidecar
    case markdownSidecar
    case htmlSidecar
    case sidecars
    case help
}

nonisolated struct CLIOptionDefinition: Sendable {
    enum Arity: Equatable, Sendable {
        case flag
        case value(String)
    }

    enum ValidationGroup: Sendable {
        case general
        case multiSizeOnly
        case batchOnly
    }

    let id: CLIOptionID
    let names: [String]
    let arity: Arity
    let terminalCaptureAllowed: Bool
    let validationGroup: ValidationGroup
    let synopsis: String
    let description: String

    var canonicalFlag: String { names[0] }
}

/// The single dependency-free schema for CLI render commands and options.
nonisolated enum CLIArgumentSchema {
    struct CommandDefinition: Sendable {
        let command: CLIOptions.Command
        let name: String
    }

    static let commands: [CommandDefinition] = CLIOptions.Command.allCases.map {
        CommandDefinition(command: $0, name: $0.rawValue)
    }

    static func command(named name: String) -> CLIOptions.Command? {
        commands.first { $0.name == name }?.command
    }

    static let options: [CLIOptionDefinition] = [
        definition(
            .out, ["--out", "-o"], .value("path"), synopsis: "-o, --out <path>",
            description: "Output image path, or folder for multi-size/batch."),
        definition(
            .quiet, ["--quiet", "-q"], .flag, synopsis: "-q, --quiet",
            description: "Suppress success output; errors still print."),
        definition(
            .json, ["--json"], .flag, synopsis: "--json",
            description: "Print render/multi-size/batch success output as JSON (not with --quiet)."),
        definition(
            .copy, ["--copy"], .flag, synopsis: "--copy",
            description: "Copy the rendered image to the clipboard.", terminalCaptureAllowed: true),
        definition(
            .edit, ["--edit", "-e"], .flag, synopsis: "-e, --edit",
            description:
                "Open the source in Vitrine's editor instead of rendering (no image is written; not with --copy/--out).",
            terminalCaptureAllowed: true),
        definition(
            .stdin, ["--stdin"], .flag, synopsis: "--stdin",
            description: "Read the source from standard input (e.g. a pipe)."),
        definition(
            .gitDiff, ["--git-diff"], .value("range"), synopsis: "--git-diff <range>",
            description:
                "Render a local Git revision/range (e.g. HEAD or main...HEAD) without invoking a shell."
        ),
        definition(
            .gitStaged, ["--git-staged"], .flag, synopsis: "--git-staged",
            description: "Render only changes staged in the local Git index."),
        definition(
            .gitPath, ["--git-path"], .value("path"), synopsis: "--git-path <path>",
            description: "Limit a Git diff source to a path. Repeat for multiple paths."),
        definition(
            .gitContext, ["--git-context"], .value("0...100"), synopsis: "--git-context <0...100>",
            description: "Unchanged lines around each Git hunk (defaults to 3)."),
        definition(
            .image, ["--image"], .value("path"), synopsis: "--image <path>",
            description: "Beautify a local image instead of rendering code."),
        definition(
            .frame, ["--frame"], .value("id"), synopsis: "--frame <id>",
            description:
                "Frame for --image: none, macos-window, browser, macbook, or iphone. Use `vitrine list frames`."
        ),
        definition(
            .frameAppearance, ["--frame-appearance"], .value("id"),
            synopsis: "--frame-appearance <id>",
            description: "Framed-image chrome: auto, light, or dark."),
        definition(
            .stdinName, ["--stdin-name", "--stdin-filename"], .value("name"),
            synopsis: "--stdin-name <name>",
            description:
                "With --stdin, infer language and default metadata from this filename; no file is read."
        ),
        definition(
            .theme, ["--theme"], .value("id"), synopsis: "--theme <id>",
            description: "Syntax theme id (e.g. one-dark, dracula, nord)."),
        definition(
            .language, ["--language", "--lang"], .value("id"), synopsis: "--language <id>",
            description: "Language id (e.g. swift, python, terminal). Inferred when omitted."),
        definition(
            .preset, ["--preset"], .value("id"), synopsis: "--preset <id>",
            description: "Destination preset. Use `vitrine list presets`."),
        definition(
            .presets, ["--presets"], .value("ids"), synopsis: "--presets <ids>",
            description:
                "Multi-size only: comma-separated destination ids, or all (the default). Use `vitrine list presets`.",
            validationGroup: .multiSizeOnly),
        definition(
            .stylePreset, ["--style-preset"], .value("id"), synopsis: "--style-preset <id>",
            description: "Built-in presentation preset. Use `vitrine list style-presets`."),
        definition(
            .recipe, ["--recipe"], .value("path"), synopsis: "--recipe <path>",
            description:
                "Load one explicit Vitrine workspace recipe. The CLI never searches parent folders or app storage."
        ),
        definition(
            .canvasSize, ["--canvas-size"], .value("WxH"), synopsis: "--canvas-size <WxH>",
            description:
                "Exact logical canvas size (64-2048 per axis). Final pixels are multiplied by --scale."
        ),
        definition(
            .scale, ["--scale"], .value("1|2|3"), synopsis: "--scale <1|2|3>",
            description:
                "Export resolution multiplier. Defaults to the app default, or the preset's recommended scale."
        ),
        definition(
            .font, ["--font"], .value("family"), synopsis: "--font <family>",
            description: "Code font family. Use `vitrine list fonts`."),
        definition(
            .fontLigatures, ["--font-ligatures"], .flag, synopsis: "--font-ligatures",
            description: "Enable programming ligatures when the font supports them."),
        definition(
            .noFontLigatures, ["--no-font-ligatures"], .flag, synopsis: "--no-font-ligatures",
            description: "Disable programming ligatures."),
        definition(
            .fontSize, ["--font-size"], .value("n"), synopsis: "--font-size <n>",
            description: "Code font size in points (10-20)."),
        definition(
            .padding, ["--padding"], .value("n"), synopsis: "--padding <n>",
            description: "Canvas padding in points (16-64)."),
        definition(
            .cornerRadius, ["--corner-radius"], .value("n"), synopsis: "--corner-radius <n>",
            description: "Code-card corner radius in points (0-48)."),
        definition(
            .shadowRadius, ["--shadow-radius"], .value("n"), synopsis: "--shadow-radius <n>",
            description: "Drop-shadow blur radius in points (0-40)."),
        definition(
            .terminalWidth, ["--terminal-width"], .value("n"), synopsis: "--terminal-width <n>",
            description:
                "Reconstruct terminal output at exactly n columns instead of inferring the width (1-1000). Only affects --language terminal; set by `vgrab -w`.",
            terminalCaptureAllowed: true),
        definition(
            .wrapColumns, ["--wrap-columns", "--wrap"], .value("n"), synopsis: "--wrap-columns <n>",
            description: "Soft-wrap long code lines at n columns (40-200)."),
        definition(
            .formatCode, ["--format-code", "--tidy"], .flag, synopsis: "--format-code",
            description: "Tidy indentation locally before rendering (--tidy is also accepted)."),
        definition(
            .format, ["--format"], .value("png|pdf|heic|avif"),
            synopsis: "--format <png|pdf|heic|avif>",
            description:
                "Output format. Defaults to png; pdf is the vector option; heic and avif are compact raster options."
        ),
        definition(
            .profile, ["--profile"], .value("srgb|p3"), synopsis: "--profile <srgb|p3>",
            description: "PNG color profile. Defaults to srgb."),
        definition(
            .transparent, ["--transparent"], .flag, synopsis: "--transparent",
            description: "Render a real transparent background."),
        definition(
            .background, ["--background"], .value("id"), synopsis: "--background <id>",
            description: "Built-in gradient. Use `vitrine list backgrounds`."),
        definition(
            .backgroundColor, ["--background-color"], .value("hex"),
            synopsis: "--background-color <hex>",
            description: "Solid RGB/RGBA hex color (for example '#1E293B')."),
        definition(
            .backgroundGradient, ["--background-gradient"], .value("hex,hex,..."),
            synopsis: "--background-gradient <hex,hex,...>",
            description: "Custom gradient with two or more RGB/RGBA colors."),
        definition(
            .backgroundAngle, ["--background-angle"], .value("degrees"),
            synopsis: "--background-angle <degrees>",
            description:
                "Custom gradient angle from 0 through 360; requires --background-gradient (defaults to 135)."
        ),
        definition(
            .backgroundImage, ["--background-image"], .value("path"),
            synopsis: "--background-image <path>",
            description: "Local image used as the canvas background."),
        definition(
            .backgroundFit, ["--background-fit"], .value("fill|fit"),
            synopsis: "--background-fit <fill|fit>",
            description: "Sizing for --background-image (defaults to fill)."),
        definition(
            .backgroundBlur, ["--background-blur"], .value("0...40"),
            synopsis: "--background-blur <0...40>",
            description: "Blur radius for --background-image in points."),
        definition(
            .backgroundDimming, ["--background-dimming"], .value("0...1"),
            synopsis: "--background-dimming <0...1>",
            description: "Dark overlay strength for --background-image."),
        definition(
            .watermark, ["--watermark"], .value("text"), synopsis: "--watermark <text>",
            description: "Add text to the rendered watermark badge."),
        definition(
            .watermarkLogo, ["--watermark-logo"], .value("path"),
            synopsis: "--watermark-logo <path>",
            description: "Add a local image to the watermark badge."),
        definition(
            .watermarkColor, ["--watermark-color"], .value("hex"),
            synopsis: "--watermark-color <hex>",
            description: "Watermark text tint; requires --watermark."),
        definition(
            .watermarkPosition, ["--watermark-position"], .value("corner|free"),
            synopsis: "--watermark-position <corner|free>",
            description:
                "Watermark placement: bottom-right, bottom-left, top-right, top-left, or free; requires watermark text or a logo."
        ),
        definition(
            .watermarkX, ["--watermark-x"], .value("0...1"), synopsis: "--watermark-x <0...1>",
            description: "Normalized horizontal center for free placement."),
        definition(
            .watermarkY, ["--watermark-y"], .value("0...1"), synopsis: "--watermark-y <0...1>",
            description:
                "Normalized vertical center for free placement; x/y must be provided together with position free."
        ),
        definition(
            .callout, ["--callout"], .value("text"), synopsis: "--callout <text>",
            description: "Add a text callout through the annotation layer."),
        definition(
            .calloutX, ["--callout-x"], .value("0...1"), synopsis: "--callout-x <0...1>",
            description: "Normalized horizontal anchor (defaults to 0.5)."),
        definition(
            .calloutY, ["--callout-y"], .value("0...1"), synopsis: "--callout-y <0...1>",
            description:
                "Normalized vertical anchor (defaults to 0.5); x/y must be provided together."),
        definition(
            .calloutColor, ["--callout-color"], .value("hex"), synopsis: "--callout-color <hex>",
            description: "Callout RGB/RGBA text color; requires --callout."),
        definition(
            .calloutSize, ["--callout-size"], .value("2...28"), synopsis: "--callout-size <2...28>",
            description: "Callout size weight; requires --callout."),
        definition(
            .counter, ["--counter"], .value("1...99"), synopsis: "--counter <1...99>",
            description: "Add a numbered annotation badge."),
        definition(
            .counterX, ["--counter-x"], .value("0...1"), synopsis: "--counter-x <0...1>",
            description: "Normalized horizontal center (defaults to 0.5)."),
        definition(
            .counterY, ["--counter-y"], .value("0...1"), synopsis: "--counter-y <0...1>",
            description:
                "Normalized vertical center (defaults to 0.5); x/y must be provided together."),
        definition(
            .counterColor, ["--counter-color"], .value("hex"), synopsis: "--counter-color <hex>",
            description: "Counter RGB/RGBA fill color; requires --counter."),
        definition(
            .counterSize, ["--counter-size"], .value("2...28"), synopsis: "--counter-size <2...28>",
            description: "Counter size weight; requires --counter."),
        definition(
            .arrow, ["--arrow"], .value("x1,y1,x2,y2"), synopsis: "--arrow <x1,y1,x2,y2>",
            description: "Add a repeatable arrow from normalized tail to head."),
        definition(
            .arrowColor, ["--arrow-color"], .value("hex"), synopsis: "--arrow-color <hex>",
            description: "RGB/RGBA stroke color for every arrow; requires --arrow."),
        definition(
            .arrowSize, ["--arrow-size"], .value("2...28"), synopsis: "--arrow-size <2...28>",
            description: "Stroke weight for every arrow; requires --arrow."),
        definition(
            .line, ["--line"], .value("x1,y1,x2,y2"), synopsis: "--line <x1,y1,x2,y2>",
            description: "Add a repeatable line between normalized coordinates."),
        definition(
            .lineColor, ["--line-color"], .value("hex"), synopsis: "--line-color <hex>",
            description: "RGB/RGBA stroke color for every line; requires --line."),
        definition(
            .lineSize, ["--line-size"], .value("2...28"), synopsis: "--line-size <2...28>",
            description: "Stroke weight for every line; requires --line."),
        definition(
            .rectangle, ["--rectangle"], .value("x1,y1,x2,y2"),
            synopsis: "--rectangle <x1,y1,x2,y2>",
            description: "Outline a repeatable normalized box."),
        definition(
            .rectangleColor, ["--rectangle-color"], .value("hex"),
            synopsis: "--rectangle-color <hex>",
            description: "Stroke color for every rectangle; requires --rectangle."),
        definition(
            .rectangleSize, ["--rectangle-size"], .value("2...28"),
            synopsis: "--rectangle-size <2...28>",
            description: "Stroke weight for every rectangle; requires --rectangle."),
        definition(
            .highlighter, ["--highlighter"], .value("x1,y1,x2,y2"),
            synopsis: "--highlighter <x1,y1,x2,y2>",
            description: "Highlight a repeatable normalized region."),
        definition(
            .highlighterColor, ["--highlighter-color"], .value("hex"),
            synopsis: "--highlighter-color <hex>",
            description: "Fill color for every highlighter; requires --highlighter."),
        definition(
            .blurBox, ["--blur-box"], .value("x1,y1,x2,y2"), synopsis: "--blur-box <x1,y1,x2,y2>",
            description: "Visually blur a repeatable region; sidecars stay unchanged."),
        definition(
            .noOverwrite, ["--no-overwrite", "--no-clobber"], .flag, synopsis: "--no-overwrite",
            description:
                "Refuse to replace existing image/sidecar outputs (--no-clobber is also accepted)."),
        definition(
            .windowTitle, ["--window-title"], .value("text"), synopsis: "--window-title <text>",
            description: "Title shown in the rendered window chrome."),
        definition(
            .filename, ["--filename"], .value("text"), synopsis: "--filename <text>",
            description: "Filename chip shown in the metadata header.", terminalCaptureAllowed: true
        ),
        definition(
            .title, ["--title"], .value("text"), synopsis: "--title <text>",
            description: "Title shown in the metadata header.", terminalCaptureAllowed: true),
        definition(
            .caption, ["--caption"], .value("text"), synopsis: "--caption <text>",
            description: "Caption shown below the metadata title."),
        definition(
            .languageBadge, ["--language-badge", "--show-language-badge"], .flag,
            synopsis: "--language-badge",
            description: "Show the language badge in the metadata header."),
        definition(
            .noLanguageBadge, ["--no-language-badge"], .flag, synopsis: "--no-language-badge",
            description: "Hide a language badge enabled by a recipe."),
        definition(
            .lineNumbers, ["--line-numbers"], .flag, synopsis: "--line-numbers",
            description: "Show the line-number gutter."),
        definition(
            .noLineNumbers, ["--no-line-numbers"], .flag, synopsis: "--no-line-numbers",
            description: "Hide the line-number gutter."),
        definition(
            .chrome, ["--chrome", "--no-chrome"], .flag, synopsis: "--chrome / --no-chrome",
            description: "Show or hide the rendered window chrome."),
        definition(
            .shadow, ["--shadow", "--no-shadow"], .flag, synopsis: "--shadow / --no-shadow",
            description: "Show or hide the rendered drop shadow."),
        definition(
            .highlightLines, ["--highlight-lines"], .value("spec"),
            synopsis: "--highlight-lines <spec>",
            description: "Highlight 1-based lines/ranges (for example 3,7-9,12)."),
        definition(
            .redactLines, ["--redact-lines"], .value("spec"), synopsis: "--redact-lines <spec>",
            description: "Redact 1-based lines/ranges; sidecars replace them with [redacted]."),
        definition(
            .redactSecrets, ["--redact-secrets"], .flag, synopsis: "--redact-secrets",
            description: "Scan for likely secrets and redact matching rows."),
        definition(
            .focusLines, ["--focus-lines", "--no-focus-lines"], .flag,
            synopsis: "--focus-lines / --no-focus-lines",
            description: "Dim or undim non-highlighted rows."),
        definition(
            .diffBands, ["--diff-bands", "--no-diff-bands"], .flag,
            synopsis: "--diff-bands / --no-diff-bands",
            description: "Show or hide GitHub-style diff line bands."),
        definition(
            .recursive, ["--recursive"], .flag, synopsis: "--recursive",
            description: "Batch only: include nested folders and preserve relative output paths.",
            validationGroup: .batchOnly),
        definition(
            .failOnSkipped, ["--fail-on-skipped"], .flag, synopsis: "--fail-on-skipped",
            description: "Batch only: exit non-zero if any file is skipped.",
            validationGroup: .batchOnly),
        definition(
            .failOnEmpty, ["--fail-on-empty"], .flag, synopsis: "--fail-on-empty",
            description: "Batch only: exit non-zero when no files would render.",
            validationGroup: .batchOnly),
        definition(
            .skippedReport, ["--skipped-report"], .value("json"),
            synopsis: "--skipped-report <json>",
            description: "Batch only: write skipped files as a JSON report.",
            validationGroup: .batchOnly),
        definition(
            .manifest, ["--manifest"], .value("json"), synopsis: "--manifest <json>",
            description: "Batch only: write rendered/planned outputs as JSON.",
            validationGroup: .batchOnly),
        definition(
            .dryRun, ["--dry-run"], .flag, synopsis: "--dry-run",
            description: "Batch only: scan/load inputs without writing images.",
            validationGroup: .batchOnly),
        definition(
            .includeExt, ["--include-ext"], .value("list"), synopsis: "--include-ext <list>",
            description:
                "Batch only: only render these comma-separated extensions (for example swift,md).",
            validationGroup: .batchOnly),
        definition(
            .excludeExt, ["--exclude-ext"], .value("list"), synopsis: "--exclude-ext <list>",
            description:
                "Batch only: ignore these comma-separated extensions before loading files.",
            validationGroup: .batchOnly),
        definition(
            .textSidecar, ["--text-sidecar"], .flag, synopsis: "--text-sidecar",
            description:
                "Also write a .txt next to --out with the source as selectable text (terminal escapes stripped)."
        ),
        definition(
            .markdownSidecar, ["--markdown-sidecar"], .flag, synopsis: "--markdown-sidecar",
            description:
                "Also write a .md next to --out: the image reference plus the source in a fenced code block, ready to paste into a README or post."
        ),
        definition(
            .htmlSidecar, ["--html-sidecar"], .flag, synopsis: "--html-sidecar",
            description:
                "Also write a .html next to --out: the image embed plus escaped source in a <pre><code> block."
        ),
        definition(
            .sidecars, ["--sidecars"], .value("list"), synopsis: "--sidecars <list>",
            description: "Enable sidecars by comma-separated list: text, markdown, html, or all."),
        definition(
            .help, ["--help", "-h"], .flag, synopsis: "-h, --help", description: "Show this help.",
            terminalCaptureAllowed: true),
    ]

    private static func definition(
        _ id: CLIOptionID,
        _ names: [String],
        _ arity: CLIOptionDefinition.Arity,
        synopsis: String,
        description: String,
        terminalCaptureAllowed: Bool = false,
        validationGroup: CLIOptionDefinition.ValidationGroup = .general
    ) -> CLIOptionDefinition {
        CLIOptionDefinition(
            id: id,
            names: names,
            arity: arity,
            terminalCaptureAllowed: terminalCaptureAllowed,
            validationGroup: validationGroup,
            synopsis: synopsis,
            description: description)
    }

    static func option(named name: String) -> CLIOptionDefinition? {
        options.first { $0.names.contains(name) }
    }

    static func option(_ id: CLIOptionID) -> CLIOptionDefinition {
        guard let definition = options.first(where: { $0.id == id }) else {
            preconditionFailure("Missing CLI option definition for \(id.rawValue)")
        }
        return definition
    }

    static var helpText: String {
        options.map(renderedHelp).joined(separator: "\n")
    }

    /// Renders stable 80-column help from the same synopsis and description the parser
    /// uses. Long option signatures take their own line; descriptions continue at the
    /// shared column instead of carrying hand-aligned whitespace in a second catalog.
    private static func renderedHelp(_ definition: CLIOptionDefinition) -> String {
        let descriptionColumn = 25
        let lineWidth = 80
        let prefix = "  \(definition.synopsis)"
        let wrapped = wrap(definition.description, width: lineWidth - descriptionColumn)
        guard !wrapped.isEmpty else { return prefix }

        var lines: [String] = []
        if prefix.count < descriptionColumn {
            lines.append(
                prefix.padding(
                    toLength: descriptionColumn,
                    withPad: " ",
                    startingAt: 0) + wrapped[0])
            lines.append(
                contentsOf: wrapped.dropFirst().map {
                    String(repeating: " ", count: descriptionColumn) + $0
                })
        } else {
            lines.append(prefix)
            lines.append(
                contentsOf: wrapped.map {
                    String(repeating: " ", count: descriptionColumn) + $0
                })
        }
        return lines.joined(separator: "\n")
    }

    private static func wrap(_ text: String, width: Int) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ").map(String.init) {
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// Enforces mode-only options from schema metadata at the same point semantic
    /// validation historically ran, preserving the established error contract.
    static func validateAvailability(
        command: CLIOptions.Command,
        seen: Set<CLIOptionID>,
        group: CLIOptionDefinition.ValidationGroup
    ) throws {
        for definition in options
        where definition.validationGroup == group
            && seen.contains(definition.id)
        {
            let isAllowed =
                switch group {
                case .general: true
                case .multiSizeOnly: command == .multiSize
                case .batchOnly: command == .batch
                }
            guard isAllowed else {
                throw CLIError.incompatibleOptions(
                    "Cannot combine \(command.rawValue) with \(definition.canonicalFlag).")
            }
        }
    }
}
