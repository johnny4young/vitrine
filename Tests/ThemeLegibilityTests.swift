import AppKit
import Observation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

private typealias BackgroundStyle = VitrineDomain.BackgroundStyle

private nonisolated final class InvalidationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() { lock.withLock { value = true } }
    var isMarked: Bool { lock.withLock { value } }
}

@MainActor
@Suite("Theme legibility")
struct ThemeLegibilityTests {
    private static let ordinaryCode = """
        import SwiftUI

        // A small counter.
        struct CounterView: View {
            @State private var count = 0

            var body: some View {
                Button("Tapped \\(count) times") {
                    count += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
        """

    private func theme(
        background: String, foreground: String, comment: String? = nil
    ) throws -> Theme {
        Theme(
            id: "custom.legibility.\(background).\(foreground).\(comment ?? "")",
            displayName: "Legibility",
            palette: ThemePalette(
                background: try #require(HexColor(background)),
                foreground: try #require(HexColor(foreground)),
                comment: comment.flatMap { HexColor($0) }))
    }

    private func config(
        _ code: String, theme: Theme, language: Language = .plaintext,
        background: BackgroundStyle = .gradient(.aurora)
    ) -> SnapshotConfig {
        var config = SnapshotConfig(code: code, language: language)
        config.theme = theme
        config.background = background
        return config
    }

    private func measure(_ config: SnapshotConfig) -> ThemeLegibility? {
        ThemeLegibility.measure(ThemeLegibility.Input(config))
    }

    @Test func whiteOnBlackMeasuresTheWCAGMaximumAndStaysQuiet() throws {
        let report = try #require(
            measure(
                config("let x = 1", theme: try theme(background: "#000000", foreground: "#FFFFFF")))
        )
        #expect(abs(try #require(report.inks.first).ratio - 21) < 0.01)
        #expect(report.lowInks.isEmpty)
        #expect(!report.isWeak)
    }

    @Test func aKnownGrayMeasuresItsPublishedRatio() throws {
        // #767676 on white is the well-known 4.54:1 AA boundary gray.
        let report = try #require(
            measure(
                config("let x = 1", theme: try theme(background: "#FFFFFF", foreground: "#767676")))
        )
        #expect(abs(try #require(report.inks.first).ratio - 4.54) < 0.01)
        #expect(report.lowInks.isEmpty)
    }

    @Test func nearInvisibleTextIsWeak() throws {
        let report = try #require(
            measure(
                config("let x = 1", theme: try theme(background: "#F4F4F4", foreground: "#EEEEEE")))
        )
        #expect(report.isWeak)
        #expect(try #require(report.lowInks.first).ratio < 1.2)
    }

    @Test(arguments: Theme.builtIns.filter { $0.id != Theme.nord.id })
    func stockThemesStayQuietOnOrdinaryCode(_ theme: Theme) throws {
        let report = try #require(
            measure(config(Self.ordinaryCode, theme: theme, language: .swift)))
        #expect(!report.isWeak, "\(theme.id): \(report.inks)")
    }

    @Test func nordsNearInvisibleCommentsWarnOnTheSameCode() throws {
        let report = try #require(
            measure(config(Self.ordinaryCode, theme: .nord, language: .swift)))
        #expect(report.isWeak)
        #expect(try #require(report.lowInks.first).ratio < 2)
    }

    @Test func aFewDimCommentsStayQuietButACommentHeavySnippetWarns() throws {
        let code = "let total = compute(input)\n// note\nlet other = compute(total)"
        let quiet = try #require(measure(config(code, theme: .oneDark, language: .swift)))
        #expect(!quiet.lowInks.isEmpty)
        #expect(!quiet.isWeak)

        let heavy = try #require(
            measure(config("// only a comment in this capture", theme: .oneDark, language: .swift)))
        #expect(heavy.isWeak)
    }

    @Test func largeTextUsesTheLargeThreshold() throws {
        // #949494 on white measures about 3.03:1: under AA at 14 pt, over it from 18 pt.
        let theme = try theme(background: "#FFFFFF", foreground: "#949494")
        var document = config("let x = 1", theme: theme)
        let normal = try #require(measure(document))
        #expect(normal.isWeak)

        document.fontSize = 18
        let large = try #require(measure(document))
        #expect(!large.isWeak)
        #expect(large.lowInks.isEmpty)
    }

    // MARK: The surface

    @Test(arguments: [
        BackgroundStyle.solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1)),
        .gradient(.sunset),
        .image(ImageBackground(reference: ImageReference(fileName: "missing.png"))),
        .transparent,
    ])
    func anOpaqueCardMakesTheBackgroundIrrelevant(
        _ background: VitrineDomain.BackgroundStyle
    ) throws {
        let code = "let x = 1"
        let reference = try #require(measure(config(code, theme: .github, language: .swift)))
        let report = try #require(
            measure(config(code, theme: .github, language: .swift, background: background)))
        #expect(report == reference)
    }

    /// The real card, read from the image the canvas draws, not from the theme's name.
    @Test(arguments: [Theme.oneDark, .github, .dracula])
    func theMeasuredCardIsTheOneTheCanvasDraws(_ theme: Theme) throws {
        var document = config(
            "x", theme: theme, background: .solid(RGBAColor(red: 1, green: 0, blue: 1, opacity: 1)))
        document.padding = 32
        let image = try #require(ExportManager.renderCGImage(document, scale: 1))
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(
                image,
                in: CGRect(
                    x: -(image.width - 44), y: -(image.height / 2), width: image.width,
                    height: image.height))
            return true
        }
        try #require(drawn)
        let card = try #require(
            HighlightManager.shared.themeChrome(for: theme).background.usingColorSpace(.sRGB))
        #expect(abs(Double(pixel[0]) / 255 - card.redComponent) < 0.01)
        #expect(abs(Double(pixel[1]) / 255 - card.greenComponent) < 0.01)
        #expect(abs(Double(pixel[2]) / 255 - card.blueComponent) < 0.01)
    }

    /// One Dark's comment gray is #5C6370 on #282C34 in its own stylesheet.
    @Test func aStockThemeIsMeasuredInItsStylesheetColors() throws {
        let report = try #require(
            measure(config("// comment", theme: .oneDark, language: .swift)))
        let ink = try #require(report.inks.first)
        #expect(ink.hex == "#5C6370FF")
        #expect(abs(ink.ratio - 2.32) < 0.05)
    }

    @Test func focusWithNothingHighlightedDimsEveryRowSoNothingIsClaimed() throws {
        let theme = try theme(background: "#FFFFFF", foreground: "#EEEEEE")
        var document = config("let x = 1", theme: theme)
        document.showLineNumbers = true
        document.focusHighlightedLines = true
        #expect(measure(document) == nil)
    }

    @Test func aTranslucentCardOverASolidWithNoShadowIsMeasured() throws {
        // A fully transparent card leaves white text directly on the solid.
        let theme = try theme(background: "#00000000", foreground: "#FFFFFF")
        var document = config(
            "let x = 1", theme: theme,
            background: .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1)))
        document.showShadow = false
        let report = try #require(measure(document))
        #expect(abs(try #require(report.inks.first).ratio - 1) < 0.01)
    }

    @Test func aHalfTranslucentCardIsMeasuredOverTheBlend() throws {
        // Black at 50.2% over white is #7F7F7F, which white text reads at 4.00:1.
        let theme = try theme(background: "#00000080", foreground: "#FFFFFF")
        var document = config(
            "let x = 1", theme: theme,
            background: .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1)))
        document.showShadow = false
        let report = try #require(measure(document))
        #expect(abs(try #require(report.inks.first).ratio - 4.0) < 0.02)
    }

    /// None of these say what's under the text: a gradient and an image vary, the others have
    /// alpha or a shadow showing through.
    @Test(arguments: [
        BackgroundStyle.transparent,
        .image(ImageBackground(reference: ImageReference(fileName: "any.png"))),
        .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 0.5)),
        .gradient(.aurora),
        .customGradient(
            CustomGradient(
                stops: [
                    GradientStop(
                        color: RGBAColor(red: 0, green: 0, blue: 0, opacity: 1), location: 0),
                    GradientStop(
                        color: RGBAColor(red: 1, green: 1, blue: 1, opacity: 1), location: 1),
                ], angle: 90)),
    ])
    func aTranslucentCardOverAnUnknownSurfaceClaimsNothing(
        _ background: VitrineDomain.BackgroundStyle
    ) throws {
        let theme = try theme(background: "#00000080", foreground: "#FFFFFF")
        var document = config("let x = 1", theme: theme, background: background)
        document.showShadow = false
        #expect(measure(document) == nil)
    }

    @Test func aTranslucentCardsShadowLeavesItsSurfaceUnknown() throws {
        let theme = try theme(background: "#00000080", foreground: "#FFFFFF")
        var document = config(
            "let x = 1", theme: theme,
            background: .solid(RGBAColor(red: 1, green: 1, blue: 1, opacity: 1)))
        document.showShadow = true
        #expect(measure(document) == nil)
    }

    /// A band changes what the text sits on, so #767676, just over AA on white, drops under it.
    @Test func aHighlightedRowIsMeasuredOnItsBand() throws {
        let theme = try theme(background: "#FFFFFF", foreground: "#767676")
        var document = config("let x = 1", theme: theme)
        #expect(try #require(measure(document)).lowInks.isEmpty)

        document.highlightedLineRanges = [1...1]
        #expect(try #require(measure(document)).lowInks.count == 1)
    }

    @Test func aDiffRowIsMeasuredOnItsBand() throws {
        let theme = try theme(background: "#FFFFFF", foreground: "#767676")
        var document = config("+ added", theme: theme)
        #expect(try #require(measure(document)).lowInks.isEmpty)

        document.diffDecorations = true
        #expect(try #require(measure(document)).lowInks.count == 1)
    }

    @Test func redactedRowsAreNotMeasured() throws {
        let theme = try theme(background: "#FFFFFF", foreground: "#111111", comment: "#EEEEEE")
        var document = config("// faint\nlet x = 1", theme: theme, language: .swift)
        #expect(try #require(measure(document)).isWeak)

        document.redactedLineRanges = [1...1]
        #expect(try #require(measure(document)).lowInks.isEmpty)
    }

    @Test func rowsDimmedByFocusAreNotMeasured() throws {
        let theme = try theme(background: "#FFFFFF", foreground: "#111111", comment: "#EEEEEE")
        var document = config("// faint\nlet x = 1", theme: theme, language: .swift)
        document.highlightedLineRanges = [2...2]
        #expect(try #require(measure(document)).isWeak)

        document.focusHighlightedLines = true
        #expect(try #require(measure(document)).lowInks.isEmpty)
    }

    @Test func nothingToMeasureReportsNothing() throws {
        #expect(measure(config(" \n\t", theme: .oneDark)) == nil)
        #expect(measure(config("", theme: .nord)) == nil)

        var image = config("", theme: .oneDark)
        image.foregroundImage = ImageReference(fileName: "capture.png")
        #expect(measure(image) == nil)

        let oversized = String(repeating: "x", count: ThemeLegibility.maximumTerminalBytes + 1)
        #expect(measure(config(oversized, theme: .oneDark, language: .terminal)) == nil)
    }

    // MARK: Terminal

    @Test func terminalTextMeasuresItsOwnColorsAndSkipsRunsWithTheirOwnBackground() throws {
        // Black on the dark terminal fill is unreadable; on an explicit white block it isn't.
        let onCard = try #require(
            measure(config("\u{1B}[30mhidden text\u{1B}[0m", theme: .oneDark, language: .terminal)))
        #expect(onCard.isWeak)

        let onBlock = try #require(
            measure(
                config(
                    "\u{1B}[30;47mblock\u{1B}[0m plain text", theme: .oneDark, language: .terminal))
        )
        #expect(!onBlock.isWeak)
    }

    @Test func aTerminalIsMeasuredInThePaletteItRendersWith() throws {
        var document = config("\u{1B}[31mred text\u{1B}[0m", theme: .github, language: .terminal)
        let theme = try #require(measure(document))
        document.terminalPalette = .raw
        let raw = try #require(measure(document))
        #expect(theme.inks.first?.hex != raw.inks.first?.hex)
    }

    // MARK: Staleness and the typing path

    @Test func everythingThatChangesTheResultChangesTheInput() throws {
        let base = config("let x = 1", theme: .github, language: .swift)
        func changes(_ change: (inout SnapshotConfig) -> Void) -> Bool {
            var changed = base
            change(&changed)
            return ThemeLegibility.Input(changed) != ThemeLegibility.Input(base)
        }
        #expect(changes { $0.code = "let y = 2" })
        #expect(changes { $0.theme = .nord })
        #expect(changes { $0.language = .terminal })
        #expect(changes { $0.terminalPalette = .raw })
        #expect(changes { $0.redactedLineRanges = [1...1] })
        #expect(changes { $0.highlightedLineRanges = [1...1] })
        #expect(changes { $0.focusHighlightedLines = true })
        #expect(changes { $0.diffDecorations = true })
        #expect(changes { $0.fontSize = 18 })
    }

    @Test func aStyleTickThatCannotChangeTheResultKeepsTheInput() throws {
        let base = config("let x = 1", theme: .github, language: .swift)
        var ticked = base
        ticked.fontSize = 15
        ticked.padding = 40
        ticked.cornerRadius = 4
        ticked.fontName = "Menlo"
        ticked.background = .gradient(.sunset)
        #expect(ThemeLegibility.Input(ticked) == ThemeLegibility.Input(base))
    }

    @Test func aBackgroundChangeUnderATranslucentCardChangesTheInput() throws {
        let theme = try theme(background: "#00000080", foreground: "#FFFFFF")
        let first = config("x", theme: theme, background: .gradient(.aurora))
        let second = config("x", theme: theme, background: .gradient(.sunset))
        #expect(ThemeLegibility.Input(first) != ThemeLegibility.Input(second))
    }

    @Test func readingTheInputDoesNotObserveTheDocumentText() {
        let settings = AppSettings(defaults: testDefaults())
        let invalidated = InvalidationProbe()
        withObservationTracking {
            _ = LegibilityMeter.input(settings: settings, code: "typed")
        } onChange: {
            invalidated.mark()
        }
        settings.config.code = "let answer = 42"
        #expect(!invalidated.isMarked)
    }

    // MARK: The offered fix

    @Test func aBetterThemeIsOfferedOnlyWhenItMeasuresBetter() throws {
        let weak = config("// only a comment in this capture", theme: .oneDark, language: .swift)
        #expect(ThemeLegibility.betterTheme(for: weak) == .githubDark)

        // GitHub's own comment gray fails on this text, so the light fix is withheld.
        let light = config("// only a comment in this capture", theme: .oneLight, language: .swift)
        #expect(ThemeLegibility.betterTheme(for: light) == nil)

        let already = config("// only a comment", theme: .githubDark, language: .swift)
        #expect(ThemeLegibility.betterTheme(for: already) == nil)
    }

    @Test func measuringChangesNothingInTheRenderedImage() throws {
        let document = config("// only a comment", theme: .oneDark, language: .swift)
        let before = ExportManager.renderCGImage(document, scale: 1).flatMap(ExportManager.pngData)
        _ = measure(document)
        _ = ThemeLegibility.betterTheme(for: document)
        #expect(
            before == ExportManager.renderCGImage(document, scale: 1).flatMap(ExportManager.pngData)
        )
    }
}
