import CoreGraphics
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import VitrineCLICore

nonisolated private let fishPath = [
    "/opt/homebrew/bin/fish", "/usr/local/bin/fish", "/usr/bin/fish",
]
.first { FileManager.default.isExecutableFile(atPath: $0) }

/// Every copied line must survive a real shell and the real parser, and rebuild the state
/// it was made from.
@MainActor
@Suite("Reproduction command")
struct CLIReproductionCommandTests: CLITestSupport {
    private func command(
        _ style: SnapshotConfig = SnapshotConfig(),
        preset: String? = nil,
        scale: Int = SettingsDefaults.exportScale,
        format: ExportFormat = .png,
        profile: ColorProfile = .fallback,
        watermark: Watermark? = nil
    ) -> CLIReproductionCommand {
        CLIReproductionCommand(
            style: style, destinationPresetID: preset, scale: scale, format: format,
            profile: profile, watermark: watermark)
    }

    private func line(_ outcome: CLIReproductionCommand.Outcome) throws -> String {
        guard case .command(let line) = outcome else {
            Issue.record("Expected a command, got \(outcome)")
            throw CLIError.missingRequired("command")
        }
        return line
    }

    /// Lets the shell itself split the line, so a quoting bug cannot hide in a test parser.
    private func shellSplit(
        _ line: String, shell: String = "/bin/sh", in directory: URL? = nil
    ) throws -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        let noConfig =
            shell.hasSuffix("zsh") ? ["-f"] : shell.hasSuffix("fish") ? ["--no-config"] : []
        process.arguments = noConfig + ["-c", "printf '%s\\0' " + line]
        process.currentDirectoryURL = directory
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init)
    }

    /// Parses the line as the CLI would and rebuilds the config it renders.
    private func options(from line: String) throws -> CLIOptions {
        let arguments = try shellSplit(line)
        #expect(arguments.first == "vitrine")
        return try CLIArguments.parse(Array(arguments.dropFirst()))
    }

    private func expectRoundTrip(
        _ command: CLIReproductionCommand,
        recipe: CLIReproductionCommand.RecipeFile? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let line = try line(command.outcome(recipe: recipe))
        let parsed = try options(from: line)
        let language = try #require(
            parsed.language ?? LanguageDetector.language(forPath: parsed.inputPath),
            sourceLocation: sourceLocation)
        var expected = command.style
        expected.code = ""
        expected.watermark = command.watermark
        #expect(
            parsed.makeConfig(code: "", language: language) == expected,
            "Round trip differs for: \(line)", sourceLocation: sourceLocation)
        #expect(parsed.presetID == command.destinationPresetID, sourceLocation: sourceLocation)
        #expect(Int(parsed.effectiveScale) == command.scale, sourceLocation: sourceLocation)
        #expect(parsed.format == command.format, sourceLocation: sourceLocation)
        #expect(parsed.profile == command.profile, sourceLocation: sourceLocation)
        #expect(parsed.fixedSize == parsed.resolvedPreset?.sizing.fixedSize)
    }

    private var customTheme: StoredCustomTheme {
        StoredCustomTheme(
            id: "custom.team", name: "Team",
            palette: ThemePalette(
                background: HexColor("#101010")!, foreground: HexColor("#F0F0F0")!))
    }

    // MARK: Quoting

    @Test func quotingLeavesInertArgumentsBareAndWrapsTheRest() {
        #expect(CLIReproductionCommand.shellQuoted("--font-size") == "--font-size")
        #expect(CLIReproductionCommand.shellQuoted("out/image.png") == "out/image.png")
        #expect(CLIReproductionCommand.shellQuoted("") == "''")
        #expect(CLIReproductionCommand.shellQuoted("Fira Code") == "'Fira Code'")
        #expect(CLIReproductionCommand.shellQuoted("it's") == "'it'\\''s'")
        #expect(CLIReproductionCommand.shellQuoted("=ls") == "'=ls'")
        #expect(CLIReproductionCommand.shellQuoted("~/x") == "'~/x'")
        #expect(CLIReproductionCommand.shellQuoted("a\\b") == "'a'\\\\'b'")
        #expect(CLIReproductionCommand.shellQuoted("\\") == "\\\\")
    }

    private func expectHostileArgumentsSurvive(shell: String) throws {
        let hostile = [
            "plain", "two words", "it's", "$(touch pwned)", "`touch pwned`", "$HOME", "=ls",
            "~/x", "#comment", "\"quoted\"", "back\\slash", "new\nline", "tab\there", "*", "?",
            "[a]", "a;b", "a|b", "a&b", "!bang", "{a,b}", "-x", "", "ñandú ✨",
            "\\'; touch pwned; echo \\'", "\\\\'; touch pwned; echo '", "trailing\\", "\\", "\\\\",
            "'", "''", "\\n", "%s",
        ]
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let split = try shellSplit(
            CLIReproductionCommand.line(hostile), shell: shell, in: directory)
        #expect(split == hostile)
        let pwned = directory.appendingPathComponent("pwned").path
        #expect(!FileManager.default.fileExists(atPath: pwned))
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh"])
    func hostileArgumentsSurviveARealShell(shell: String) throws {
        try expectHostileArgumentsSurvive(shell: shell)
    }

    @Test(.enabled(if: fishPath != nil, "fish is not installed on this machine"))
    func hostileArgumentsSurviveFish() throws {
        try expectHostileArgumentsSurvive(shell: try #require(fishPath))
    }

    // MARK: Mapping

    @Test func defaultsNeedOnlyAnInputAndAnOutput() throws {
        #expect(try line(command().outcome()) == "vitrine render input.swift --out image.png")
        try expectRoundTrip(command())
    }

    @Test func everyFlagTheMappingEmitsParsesBackToTheSameState() throws {
        var style = SnapshotConfig()
        style.language = .python
        style.theme = Theme.theme(withID: "dracula")
        style.fontName = "Fira Code"
        style.fontSize = 16.5
        style.fontLigatures = true
        style.padding = 48
        style.cornerRadius = 12
        style.showShadow = false
        style.shadowRadius = 8
        style.showChrome = false
        style.showLineNumbers = true
        style.wrapColumns = 80
        style.background = .solid(RGBAColor(hex: "#1E293B")!)
        style.windowTitle = "it's a title"
        style.metadata = SnapshotMetadata(
            filename: "main.py", title: "$(title)", caption: "line one\nline two",
            showLanguageBadge: true)
        style.highlightedLineRanges = [3...3, 7...9]
        style.redactedLineRanges = [12...12]
        style.focusHighlightedLines = true
        style.diffDecorations = true
        style.terminalColumns = 100
        let watermark = Watermark(
            text: "@team · vitrine", tint: RGBAColor(hex: "#FF0000"), placement: .free,
            freePosition: CGPoint(x: 0.25, y: 0.75))
        try expectRoundTrip(
            command(style, scale: 3, format: .pdf, profile: .displayP3, watermark: watermark))
    }

    @Test func backgroundsAndCornerWatermarksMapToTheirFlags() throws {
        var style = SnapshotConfig()
        for gradient in GradientPreset.allCases where gradient != .aurora {
            style.background = .gradient(gradient)
            try expectRoundTrip(command(style))
        }
        style.background = .transparent
        try expectRoundTrip(command(style))
        style.background = .customGradient(
            CustomGradient(
                stops: [
                    GradientStop(color: RGBAColor(hex: "#111111")!, location: 0),
                    GradientStop(color: RGBAColor(hex: "#222222")!, location: 0.5),
                    GradientStop(color: RGBAColor(hex: "#333333")!, location: 1),
                ], angle: 45))
        try expectRoundTrip(command(style))
        for placement in [Watermark.Placement.bottomLeading, .topLeading, .topTrailing] {
            try expectRoundTrip(
                command(watermark: Watermark(text: "mark", placement: placement)))
        }
    }

    @Test func destinationsThemesAndLanguagesAllReachTheParser() throws {
        for preset in ExportPreset.all {
            var style = SnapshotConfig().styled(
                presetID: preset.id, themeID: nil, transparent: false)
            style.padding = preset.padding == 40 ? 41 : 40
            try expectRoundTrip(command(style, preset: preset.id, scale: preset.scale))
            try expectRoundTrip(command(style, preset: preset.id, scale: preset.scale % 3 + 1))
        }
        for theme in Theme.builtIns where theme != SnapshotConfig().theme {
            var style = SnapshotConfig()
            style.theme = theme
            try expectRoundTrip(command(style))
        }
        for language in Language.allCases {
            var style = SnapshotConfig()
            style.language = language
            try expectRoundTrip(command(style))
        }
        for format in ExportFormat.allCases {
            try expectRoundTrip(command(format: format))
        }
    }

    @Test func sourceTextNeverReachesTheLineAndRedactionTravelsAsLineNumbers() throws {
        var style = SnapshotConfig(code: "let secret = \"hunter2\"", language: .swift)
        style.redactedLineRanges = [1...1]
        let line = try line(command(style).outcome())
        #expect(!line.contains("hunter2"))
        #expect(line.contains("--redact-lines 1 --redact-secrets"))
    }

    @Test func onlyTheLeafOfAFilenameTravels() throws {
        for path in ["/Users/me/Code/main.swift", "C:\\Code\\main.swift"] {
            var style = SnapshotConfig()
            style.metadata = SnapshotMetadata(filename: path)
            let line = try line(command(style).outcome())
            #expect(line.hasSuffix("--filename main.swift"), "\(line)")
        }
    }

    // MARK: Limits

    @Test func statesWithoutAFlagNameTheirLimitInsteadOfAWrongCommand() throws {
        var annotated = SnapshotConfig()
        annotated.annotations = [
            Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))
        ]
        #expect(command(annotated).outcome() == .unavailable([.annotations]))

        var image = SnapshotConfig()
        image.foregroundImage = ImageReference(fileName: "pasted.png")
        #expect(command(image).outcome() == .unavailable([.pastedImage]))

        var background = SnapshotConfig()
        background.background = .image(
            ImageBackground(reference: ImageReference(fileName: "b.png")))
        #expect(command(background).outcome() == .unavailable([.imageBackground]))

        var themed = SnapshotConfig()
        themed.theme = customTheme.theme
        #expect(command(themed).outcome() == .unavailable([.customTheme]))

        var uneven = SnapshotConfig()
        uneven.background = .customGradient(
            CustomGradient(
                stops: [
                    GradientStop(color: RGBAColor(hex: "#111111")!, location: 0),
                    GradientStop(color: RGBAColor(hex: "#222222")!, location: 0.2),
                    GradientStop(color: RGBAColor(hex: "#333333")!, location: 1),
                ], angle: 45))
        #expect(command(uneven).outcome() == .unavailable([.customGradient]))

        for mark in [
            Watermark(text: "", logoImageData: Data([1])),
            Watermark(text: "mark", qrIdentity: "https://example.com"),
            Watermark(text: "mark", placement: .footerBar),
        ] {
            #expect(command(watermark: mark).outcome() == .unavailable([.brandMark]))
        }

        var both = annotated
        both.theme = customTheme.theme
        #expect(command(both).outcome() == .unavailable([.annotations, .customTheme]))
    }

    @Test(arguments: ["\u{1B}[2Jtitle", "a\u{07}", "a\u{0D}b", "a\u{7F}", "a\u{9B}31m", "\u{00}"])
    func controlCharactersAreRefusedButNewlinesAndTabsAreNot(text: String) throws {
        var style = SnapshotConfig()
        style.metadata = SnapshotMetadata(title: text)
        #expect(command(style).outcome() == .unavailable([.controlCharacters]))
        style.metadata = SnapshotMetadata(caption: "one\ntwo\tthree")
        _ = try line(command(style).outcome())
    }

    /// Assembled at runtime, so the fixture itself never looks like a committed secret.
    private var likelyToken: String { "ghp_" + String(repeating: "a1", count: 18) }

    @Test func aLikelySecretInAnyTextFlagRefusesTheLine() throws {
        let secret = likelyToken
        var window = SnapshotConfig()
        window.windowTitle = secret
        var title = SnapshotConfig()
        title.metadata = SnapshotMetadata(title: "Key \(secret)")
        var caption = SnapshotConfig()
        caption.metadata = SnapshotMetadata(caption: secret)
        var filename = SnapshotConfig()
        filename.metadata = SnapshotMetadata(filename: secret)
        for style in [window, title, caption, filename] {
            #expect(command(style).outcome() == .unavailable([.likelySecret]))
        }
        #expect(
            command(watermark: Watermark(text: secret)).outcome() == .unavailable([.likelySecret]))
    }

    // MARK: Recipes

    private func recipeFile(
        _ recipe: WorkspaceRecipe, in directory: URL
    ) throws -> CLIReproductionCommand.RecipeFile {
        let name = "my team's.vitrine-recipe.json"
        let url = directory.appendingPathComponent(name)
        try WorkspaceRecipeDocument(recipe: recipe).validatedJSONData().write(to: url)
        return CLIReproductionCommand.RecipeFile(relativePath: name, recipe: recipe)
    }

    /// The line references the recipe from its workspace, so it parses from there.
    private func inDirectory(_ directory: URL, _ body: () throws -> Void) throws {
        let manager = FileManager.default
        let previous = manager.currentDirectoryPath
        #expect(manager.changeCurrentDirectoryPath(directory.path))
        defer { manager.changeCurrentDirectoryPath(previous) }
        try body()
    }

    /// The state the app holds after applying `recipe`, built the way the CLI builds it.
    private func applied(_ recipe: WorkspaceRecipe) -> SnapshotConfig {
        var style = SnapshotConfig().styled(
            presetID: recipe.output.destinationPresetID, themeID: nil, transparent: false)
        recipe.style.apply(to: &style, resolvingThemeWith: recipe.theme(withID:))
        style.windowTitle = recipe.metadata.windowTitle ?? ""
        style.metadata = recipe.metadata.header
        return style
    }

    @Test func aDocumentOnThemeOverridesARawRecipe() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = WorkspaceRecipe(
            name: "Raw",
            style: StyleSnapshot(
                themeID: Theme.oneDark.id, terminalPalette: .raw, background: .gradient(.aurora)))
        let file = try recipeFile(recipe, in: directory)
        var style = applied(recipe)
        style.language = .terminal
        #expect(style.terminalPalette == .raw)
        let matching = try line(command(style).outcome(recipe: file))
        #expect(!matching.contains("--terminal-palette"))

        style.terminalPalette = .theme
        let overriding = command(style)
        #expect(try line(overriding.outcome(recipe: file)).contains("--terminal-palette theme"))
        try inDirectory(directory) { try expectRoundTrip(overriding, recipe: file) }
    }

    @Test func aDocumentWithoutACursorOverridesARecipeWithOne() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = WorkspaceRecipe(
            name: "Bar",
            style: StyleSnapshot(
                themeID: Theme.oneDark.id, terminalCursor: .bar, background: .gradient(.aurora)))
        let file = try recipeFile(recipe, in: directory)
        var style = applied(recipe)
        style.language = .terminal
        #expect(style.terminalCursor == .bar)
        #expect(try !line(command(style).outcome(recipe: file)).contains("--terminal-cursor"))

        style.terminalCursor = .hidden
        let overriding = command(style)
        #expect(try line(overriding.outcome(recipe: file)).contains("--terminal-cursor hidden"))
        try inDirectory(directory) { try expectRoundTrip(overriding, recipe: file) }
    }

    @Test func aMatchingRecipeNeedsOnlyItsPathAndFlagsOverrideTheRest() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = try WorkspaceRecipeFile.load(
            from: repoFile("docs", "examples", "documentation.vitrine-recipe.json"))
        let file = try recipeFile(recipe, in: directory)
        var style = applied(recipe)
        let scale = recipe.output.scale ?? SettingsDefaults.exportScale
        let preset = recipe.output.destinationPresetID

        let exact = command(style, preset: preset, scale: scale)
        let exactLine = try line(exact.outcome(recipe: file))
        #expect(
            exactLine
                == "vitrine render input.swift --out image.png --recipe "
                + CLIReproductionCommand.shellQuoted(try #require(file.relativePath)))
        #expect(!exactLine.contains(directory.path))
        try inDirectory(directory) { try expectRoundTrip(exact, recipe: file) }

        style.theme = Theme.theme(withID: "dracula")
        style.padding = 20
        let overridden = command(style, preset: "twitter", scale: 2, profile: .displayP3)
        let overriddenLine = try line(overridden.outcome(recipe: file))
        #expect(overriddenLine.contains("--theme dracula"))
        #expect(overriddenLine.contains("--preset twitter"))
        try inDirectory(directory) { try expectRoundTrip(overridden, recipe: file) }
    }

    @Test func aRecipeCarriesWhatFlagsCannot() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recipe = WorkspaceRecipe(
            name: "Team",
            style: StyleSnapshot(themeID: customTheme.id, background: .gradient(.aurora)),
            customTheme: customTheme)
        let file = try recipeFile(recipe, in: directory)
        let themed = command(applied(recipe))
        #expect(themed.outcome() == .unavailable([.customTheme]))
        try inDirectory(directory) { try expectRoundTrip(themed, recipe: file) }
    }

    @Test func aRecipeOutsideItsWorkspaceIsNeverReferencedByAbsolutePath() throws {
        let recipe = WorkspaceRecipe(
            name: "Team",
            style: StyleSnapshot(themeID: customTheme.id, background: .gradient(.aurora)),
            customTheme: customTheme)
        let outside = CLIReproductionCommand.RecipeFile(relativePath: nil, recipe: recipe)
        #expect(
            command(applied(recipe)).outcome(recipe: outside)
                == .unavailable([.recipeOutsideWorkspace]))

        // Flags alone can express this state, so the line simply omits the recipe.
        let plain = WorkspaceRecipe(
            name: "Plain",
            style: StyleSnapshot(themeID: Theme.oneDark.id, background: .gradient(.aurora)))
        let line = try line(
            command(applied(plain)).outcome(recipe: .init(relativePath: nil, recipe: plain)))
        #expect(!line.contains("--recipe"))
    }

    @Test func aRecipeThatNoFlagCanUndoFallsBackToPlainFlags() throws {
        let base = StyleSnapshot(themeID: Theme.oneDark.id, background: .gradient(.aurora))
        let path = "unused.json"
        let cases: [WorkspaceRecipe] = [
            WorkspaceRecipe(
                name: "Canvas", style: base,
                output: .init(canvasSize: .init(width: 800, height: 600))),
            WorkspaceRecipe(
                name: "Destination", style: base, output: .init(destinationPresetID: "twitter")),
            WorkspaceRecipe(
                name: "Wrap",
                style: StyleSnapshot(
                    themeID: Theme.oneDark.id, wrapColumns: 80, background: .gradient(.aurora))),
            WorkspaceRecipe(
                name: "Window", style: base, metadata: .init(windowTitle: "Window")),
            WorkspaceRecipe(
                name: "Header", style: base,
                metadata: .init(header: SnapshotMetadata(filename: "a.swift"))),
            WorkspaceRecipe(
                name: "Title", style: base, metadata: .init(header: SnapshotMetadata(title: "T"))),
            WorkspaceRecipe(
                name: "Caption", style: base,
                metadata: .init(header: SnapshotMetadata(caption: "C"))),
        ]
        for recipe in cases {
            let line = try line(
                command().outcome(recipe: .init(relativePath: path, recipe: recipe)))
            #expect(line == "vitrine render input.swift --out image.png", "\(recipe.name)")
        }
    }
}
