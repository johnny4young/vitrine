import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import Vitrine

// MARK: - Shared fixtures

/// The canonical models the render and golden suites share, so the bytes that are
/// recorded and the bytes that are compared come from the exact same input.
enum SocialCardFixtures {
    /// The default-template card used for the golden fixture (CS-041 "golden image
    /// fixture for default template"). Every pixel-affecting field is pinned: the
    /// signature template, theme, background, and the bundled JetBrains Mono font.
    static let defaultCard = SocialCardModel(
        title: "Ship beautiful code screenshots",
        subtitle: "Render, theme, and share — entirely on your Mac.",
        codeExcerpt: """
            func greet(_ name: String) -> String {
                "Hello, \\(name)!"
            }
            """,
        language: .swift,
        author: "@vitrine",
        project: "vitrine",
        showLogo: true,
        template: .standard,
        theme: .oneDark,
        background: .gradient(.aurora),
        fontName: CodeFont.default,
        fontSize: 22
    )
}

/// Locates the committed social-card fixtures directory in the source tree
/// (`<repo>/Tests/Fixtures/SocialCards/`), anchored to this file via `#filePath`
/// just like `GoldenPaths` does for the CS-025 fixtures.
enum SocialCardGoldenPaths {
    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("SocialCards", isDirectory: true)
    }

    /// The default-template golden PNG.
    static let defaultFixtureName = "default-card.png"

    static var defaultFixtureURL: URL {
        fixturesDirectory.appendingPathComponent(defaultFixtureName)
    }

    static var manifestURL: URL {
        GoldenManifest.url(in: fixturesDirectory)
    }
}

// MARK: - Model validation (CS-041 "model validation")

@Suite("SocialCardModel validation (CS-041)")
struct SocialCardModelValidationTests {
    @Test func blankTextFieldsNormalizeToNil() {
        let card = SocialCardModel(
            title: "   ", subtitle: "\n\t ", codeExcerpt: "let x = 1", author: "",
            project: "  \n")
        #expect(card.title == nil)
        #expect(card.subtitle == nil)
        #expect(card.author == nil)
        #expect(card.project == nil)
    }

    @Test func textFieldsAreTrimmed() {
        let card = SocialCardModel(
            title: "  Hello  ", subtitle: "\tWorld\n", author: " @jane ", project: " repo ")
        #expect(card.title == "Hello")
        #expect(card.subtitle == "World")
        #expect(card.author == "@jane")
        #expect(card.project == "repo")
    }

    @Test func anEmptyModelIsNotRenderable() {
        // No title and no excerpt: the renderer must refuse it rather than produce a
        // blank image.
        #expect(!SocialCardModel().isRenderable)
        #expect(!SocialCardModel(title: "   ", codeExcerpt: "   ").isRenderable)
    }

    @Test func aTitleOrAnExcerptMakesItRenderable() {
        #expect(SocialCardModel(title: "Hi").isRenderable)
        #expect(SocialCardModel(codeExcerpt: "let x = 1").isRenderable)
    }

    @Test func headlineTemplateNeedsTitleOrSubtitleNotJustAnExcerpt() {
        // The headline template drops the code panel, so an excerpt alone would
        // render a blank card — renderability must require a title or subtitle.
        #expect(
            !SocialCardModel(codeExcerpt: "let x = 1", template: .headline).isRenderable,
            "a headline card with only an excerpt is blank; it must be refused")
        #expect(SocialCardModel(title: "Announcing", template: .headline).isRenderable)
        #expect(SocialCardModel(subtitle: "A subtitle", template: .headline).isRenderable)
    }

    @Test func codeBearingTemplatesStayRenderableFromAnExcerptAlone() {
        // The standard and code-focus templates do draw the excerpt, so an excerpt
        // with no title is still renderable for them.
        #expect(SocialCardModel(codeExcerpt: "let x = 1", template: .standard).isRenderable)
        #expect(SocialCardModel(codeExcerpt: "let x = 1", template: .codeFocus).isRenderable)
    }

    @Test func excerptIsTruncatedToTheDocumentedLineCap() {
        // A 20-line input is capped at maxExcerptLines, plus a trailing ellipsis
        // marker, so a card can never turn into a full-file screenshot.
        let manyLines = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let card = SocialCardModel(codeExcerpt: manyLines)
        let lines = card.excerptLines
        #expect(lines.count == SocialCardModel.maxExcerptLines + 1)
        #expect(lines.last == "…")
        #expect(lines.first == "line 1")
    }

    @Test func shortExcerptIsKeptVerbatimWithNoEllipsis() {
        let card = SocialCardModel(codeExcerpt: "a\nb\nc")
        #expect(card.excerptLines == ["a", "b", "c"])
        #expect(card.codeExcerpt == "a\nb\nc")
    }

    @Test func excerptTrimsSurroundingBlankLines() {
        let card = SocialCardModel(codeExcerpt: "\n\n  let x = 1  \n\n")
        #expect(card.codeExcerpt == "let x = 1")
        #expect(!card.codeExcerpt.isEmpty)
    }

    @Test func emptyExcerptHasNoLines() {
        let card = SocialCardModel(title: "Only a title")
        #expect(card.codeExcerpt.isEmpty)
        #expect(card.excerptLines.isEmpty)
    }

    @Test func fontSizeIsClampedIntoRange() {
        #expect(SocialCardModel(fontSize: 1).fontSize == SocialCardModel.fontSizeRange.lowerBound)
        #expect(
            SocialCardModel(fontSize: 9999).fontSize == SocialCardModel.fontSizeRange.upperBound)
        #expect(SocialCardModel(fontSize: 24).fontSize == 24)
    }

    @Test func nonFiniteFontSizeFallsBackToDefault() {
        #expect(SocialCardModel(fontSize: .nan).fontSize == SocialCardModel.defaultFontSize)
        #expect(SocialCardModel(fontSize: .infinity).fontSize == SocialCardModel.defaultFontSize)
    }

    @Test func hasFooterReflectsAuthorOrProject() {
        #expect(!SocialCardModel(title: "x").hasFooter)
        #expect(SocialCardModel(title: "x", author: "@a").hasFooter)
        #expect(SocialCardModel(title: "x", project: "p").hasFooter)
    }

    @Test func defaultSizeIsTheOpenGraphCard() {
        #expect(SocialCardModel.defaultSize == CGSize(width: 1200, height: 630))
    }
}

// MARK: - Template catalog

@Suite("SocialCardTemplate catalog (CS-041)")
struct SocialCardTemplateTests {
    @Test func everyTemplateIsNamedAndDescribed() {
        for template in SocialCardTemplate.allCases {
            #expect(!template.displayName.isEmpty)
            #expect(!template.summary.isEmpty)
        }
    }

    @Test func idsAreUniqueAndStable() {
        let ids = SocialCardTemplate.allCases.map(\.id)
        #expect(Set(ids).count == ids.count)
        // The raw values are the on-disk identifiers; pin them so a rename is a
        // deliberate, reviewed change rather than a silent persistence break.
        #expect(Set(ids) == ["standard", "codeFocus", "headline"])
    }

    @Test func onlyHeadlineOmitsTheCodePanel() {
        #expect(SocialCardTemplate.standard.showsCode)
        #expect(SocialCardTemplate.codeFocus.showsCode)
        #expect(!SocialCardTemplate.headline.showsCode)
    }

    @Test func resolveToleratesUnknownAndNil() {
        #expect(SocialCardTemplate.resolve("standard") == .standard)
        #expect(SocialCardTemplate.resolve("headline") == .headline)
        #expect(SocialCardTemplate.resolve("does-not-exist") == .fallback)
        #expect(SocialCardTemplate.resolve(nil) == .fallback)
    }
}

// MARK: - Codable round-trip + tolerance

@Suite("SocialCardModel Codable (CS-041)")
struct SocialCardModelCodableTests {
    @Test func roundTripsThroughJSON() throws {
        let original = SocialCardFixtures.defaultCard
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SocialCardModel.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTripPreservesEveryTemplateAndBackground() throws {
        let backgrounds: [BackgroundStyle] = [
            .gradient(.aurora), .solid(.white), .transparent,
            .customGradient(.default),
        ]
        for template in SocialCardTemplate.allCases {
            for background in backgrounds {
                let card = SocialCardModel(
                    title: "T", codeExcerpt: "x", template: template, background: background)
                let data = try JSONEncoder().encode(card)
                let decoded = try JSONDecoder().decode(SocialCardModel.self, from: data)
                #expect(decoded == card)
            }
        }
    }

    @Test func unknownThemeAndLanguageDegradeToDefaults() throws {
        // A hand-edited blob with an unknown theme/language must not crash the
        // decode; it degrades to the documented defaults (CS-050 spirit).
        let json = """
            {"title":"Hi","codeExcerpt":"x","language":"klingon","theme":"no-such-theme",\
            "template":"standard","background":{"kind":"gradient","preset":"Aurora"},\
            "fontName":"JetBrains Mono","fontSize":22,"showLogo":false}
            """
        let decoded = try JSONDecoder().decode(SocialCardModel.self, from: Data(json.utf8))
        #expect(decoded.language == .swift)
        #expect(decoded.theme.id == Theme.oneDark.id)
    }

    @Test func corruptFontSizeAndExcerptAreReSanitizedOnDecode() throws {
        let manyLines = (1...30).map { "l\($0)" }.joined(separator: "\\n")
        let json = """
            {"title":"Hi","codeExcerpt":"\(manyLines)","language":"swift","theme":"one-dark",\
            "template":"standard","background":{"kind":"gradient","preset":"Aurora"},\
            "fontName":"JetBrains Mono","fontSize":100000,"showLogo":false}
            """
        let decoded = try JSONDecoder().decode(SocialCardModel.self, from: Data(json.utf8))
        #expect(decoded.fontSize == SocialCardModel.fontSizeRange.upperBound)
        #expect(decoded.excerptLines.count == SocialCardModel.maxExcerptLines + 1)
    }

    @Test func missingBackgroundDegradesToSignatureGradient() throws {
        let json = """
            {"title":"Hi","codeExcerpt":"x","language":"swift","theme":"one-dark",\
            "template":"standard","fontName":"JetBrains Mono","fontSize":22,"showLogo":false}
            """
        let decoded = try JSONDecoder().decode(SocialCardModel.self, from: Data(json.utf8))
        #expect(decoded.background == .gradient(.aurora))
    }
}

// MARK: - Fingerprint determinism

@Suite("SocialCardModel fingerprint (CS-041)")
struct SocialCardFingerprintTests {
    @Test func fingerprintIsStableAcrossCalls() {
        let card = SocialCardFixtures.defaultCard
        #expect(card.fingerprint == card.fingerprint)
        #expect(card.fingerprint.count == 64, "fingerprint is not a full SHA-256 hex digest")
    }

    @Test func fingerprintDiscriminatesEveryRenderedField() {
        let base = SocialCardFixtures.defaultCard
        var distinct: Set<String> = [base.fingerprint]
        func expectChanged(_ mutate: (inout SocialCardModel) -> Void) {
            var copy = base
            mutate(&copy)
            #expect(
                distinct.insert(copy.fingerprint).inserted,
                "a pixel-affecting change did not move the fingerprint")
        }
        expectChanged { $0.title = "Different" }
        expectChanged { $0.subtitle = "Different subtitle" }
        expectChanged { $0.codeExcerpt = "let y = 2" }
        expectChanged { $0.language = .python }
        expectChanged { $0.author = "@other" }
        expectChanged { $0.project = "other-repo" }
        expectChanged { $0.showLogo = false }
        expectChanged { $0.template = .codeFocus }
        expectChanged { $0.theme = .dracula }
        expectChanged { $0.fontName = "Fira Code" }
        expectChanged { $0.fontSize = 30 }
        expectChanged { $0.background = .solid(.white) }
    }
}

// MARK: - Render dimensions (CS-041 "render dimensions")

@MainActor
@Suite("Social card render dimensions (CS-041)")
struct SocialCardRenderDimensionTests {
    @Test func defaultRenderIsExactly1200x630At1x() throws {
        // The headline acceptance: the default export is 1200×630. `ImageRenderer`
        // honors the pinned proposedSize, so this dimension is OS-independent and is
        // asserted on every runner.
        let image = try #require(
            SocialCardRenderer.renderCGImage(SocialCardFixtures.defaultCard, scale: 1))
        #expect(image.width == 1200)
        #expect(image.height == 630)
    }

    @Test func renderScalesWithTheResolutionMultiplier() throws {
        let image = try #require(
            SocialCardRenderer.renderCGImage(SocialCardFixtures.defaultCard, scale: 2))
        #expect(image.width == 2400)
        #expect(image.height == 1260)
    }

    @Test func everyTemplateRendersAtTheFixedSize() throws {
        for template in SocialCardTemplate.allCases {
            var card = SocialCardFixtures.defaultCard
            card.template = template
            let image = try #require(
                SocialCardRenderer.renderCGImage(card, scale: 1),
                "render produced no image for \(template.rawValue)")
            #expect(image.width == 1200 && image.height == 630)
        }
    }

    @Test func aCustomFixedSizeIsHonored() throws {
        let size = CGSize(width: 800, height: 800)
        let image = try #require(
            SocialCardRenderer.renderCGImage(SocialCardFixtures.defaultCard, size: size, scale: 1))
        #expect(image.width == 800 && image.height == 800)
    }

    @Test func anEmptyModelRendersNothing() {
        // The renderer refuses an empty model across every entry point rather than
        // emitting a blank card.
        let empty = SocialCardModel()
        #expect(SocialCardRenderer.renderCGImage(empty) == nil)
        #expect(SocialCardRenderer.renderNSImage(empty) == nil)
        #expect(SocialCardRenderer.pdfData(empty) == nil)
        #expect(SocialCardRenderer.copyToPasteboard(empty) == false)
    }

    @Test func aHeadlineCardWithOnlyAnExcerptIsRefused() {
        // The headline template never draws the excerpt, so a headline model that
        // carries only a code excerpt would render blank — the renderer must refuse
        // it instead of emitting an empty card.
        let blankHeadline = SocialCardModel(codeExcerpt: "let x = 1", template: .headline)
        #expect(SocialCardRenderer.renderCGImage(blankHeadline) == nil)
        #expect(SocialCardRenderer.renderNSImage(blankHeadline) == nil)
        #expect(SocialCardRenderer.pdfData(blankHeadline) == nil)
        #expect(SocialCardRenderer.copyToPasteboard(blankHeadline) == false)
    }

    @Test func aCodeFocusCardWithNoExcerptStillRendersAtTheFixedSize() throws {
        // A code-focus card with a title but an empty excerpt is renderable; it
        // degrades to the headline + footer (no empty code box) and still renders at
        // the guaranteed 1200×630.
        let card = SocialCardModel(title: "Just a headline", template: .codeFocus)
        let image = try #require(SocialCardRenderer.renderCGImage(card, scale: 1))
        #expect(image.width == 1200 && image.height == 630)
    }

    @Test func nsImageAndPDFAndPNGAllProduceForARenderableCard() throws {
        let card = SocialCardFixtures.defaultCard
        let nsImage = try #require(SocialCardRenderer.renderNSImage(card, scale: 1))
        #expect(nsImage.size.width == 1200 && nsImage.size.height == 630)

        let pdf = try #require(SocialCardRenderer.pdfData(card))
        // A single-page PDF starts with the "%PDF" signature.
        #expect(pdf.prefix(4) == Data("%PDF".utf8))

        let cgImage = try #require(SocialCardRenderer.renderCGImage(card, scale: 1))
        let png = try #require(ExportManager.pngData(from: cgImage))
        #expect(png.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test func transparentBackgroundKeepsRealAlpha() throws {
        // A transparent-background card must export with a real alpha channel and no
        // opaque matte, the same CS-024 guarantee a snapshot has.
        var card = SocialCardFixtures.defaultCard
        card.background = .transparent
        let image = try #require(SocialCardRenderer.renderCGImage(card, scale: 1))
        #expect(image.alphaInfo != .none, "a transparent card must carry an alpha channel")
    }
}

// MARK: - Rendered content (CS-041 "templates render title, subtitle, code excerpt, …")

/// Proves the templates actually *draw* each acceptance field, not merely model
/// it. The dimension and fingerprint suites confirm the model reacts to a field
/// and the render keeps its size, but a field could silently fail to paint and
/// every one of those checks would still pass. Here two cards that differ only in
/// one rendered field are rasterized at the same fixed size and diffed pixel-for-
/// pixel through the CS-025 comparator: if the field is genuinely drawn, the
/// images diverge far past the anti-aliasing floor; if it is dropped, they would
/// match and the test fails. This is the render-level counterpart to the model's
/// `fingerprint` test.
@MainActor
@Suite("Social card rendered content (CS-041)")
struct SocialCardRenderedContentTests {
    /// Renders `lhs` and `rhs` at the same 1200×630 size and returns the fraction of
    /// pixels that differ beyond the comparator's per-channel tolerance.
    private func differingFraction(
        _ lhs: SocialCardModel, _ rhs: SocialCardModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Double {
        let a = try #require(
            SocialCardRenderer.renderCGImage(lhs, scale: 1), "left render produced no image",
            sourceLocation: sourceLocation)
        let b = try #require(
            SocialCardRenderer.renderCGImage(rhs, scale: 1), "right render produced no image",
            sourceLocation: sourceLocation)
        switch GoldenComparator.compare(a, b) {
        case .success(let result):
            return result.differingFraction
        case .failure(let failure):
            Issue.record("comparison failed: \(failure)", sourceLocation: sourceLocation)
            return 0
        }
    }

    /// Asserts the two cards render visibly differently — well past the comparator's
    /// `pixelFractionTolerance` noise floor, so only a genuinely drawn change passes.
    private func expectVisiblyDifferent(
        _ lhs: SocialCardModel, _ rhs: SocialCardModel, _ field: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let fraction = try differingFraction(lhs, rhs, sourceLocation: sourceLocation)
        let percent = String(format: "%.5f", fraction)
        #expect(
            fraction > GoldenComparator.pixelFractionTolerance,
            "changing \(field) moved only \(percent) of pixels — it is not being rendered",
            sourceLocation: sourceLocation)
    }

    @Test func standardTemplateRendersTitleSubtitleExcerptAuthorProjectAndLogo() throws {
        // One base card with every field populated; drop each field in turn and prove
        // the rendered pixels change, i.e. the field was actually on the card.
        let full = SocialCardModel(
            title: "A bold headline", subtitle: "A supporting subtitle",
            codeExcerpt: "let answer = 42", language: .swift,
            author: "@jane", project: "vitrine", showLogo: true, template: .standard)

        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.title = nil
                return c
            }(), "the title")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.subtitle = nil
                return c
            }(), "the subtitle")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.codeExcerpt = ""
                return c
            }(), "the code excerpt")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.author = nil
                return c
            }(), "the author")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.project = nil
                return c
            }(), "the project")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.showLogo = false
                return c
            }(), "the logo")
    }

    @Test func headlineTemplateRendersTitleSubtitleAndLogo() throws {
        // The headline template has no code panel, so it must still draw the title,
        // subtitle, and logo it is responsible for.
        let full = SocialCardModel(
            title: "Announcing", subtitle: "Something new", author: "@jane",
            showLogo: true, template: .headline)
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.title = nil
                return c
            }(), "the title")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.subtitle = nil
                return c
            }(), "the subtitle")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.showLogo = false
                return c
            }(), "the logo")
        try expectVisiblyDifferent(
            full,
            {
                var c = full
                c.author = nil
                return c
            }(), "the author")
    }

    @Test func excerptContentAndHighlightingThemeAreRendered() throws {
        // Two different multi-line snippets (filling the panel with distinct glyphs on
        // every row), and the same snippet under a different theme, must both change the
        // drawn code panel — proving the excerpt text is laid out and the theme recolors
        // it, rather than a fixed placeholder being painted.
        let codeA = """
            func greet(_ name: String) -> String {
                let greeting = "Hello, \\(name)!"
                return greeting
            }
            """
        let codeB = """
            struct Point: Equatable {
                var x: Double = 0
                var y: Double = 0
            }
            """
        let base = SocialCardModel(
            title: "T", codeExcerpt: codeA, language: .swift, template: .standard, theme: .oneDark)
        try expectVisiblyDifferent(
            base,
            {
                var c = base
                c.codeExcerpt = codeB
                return c
            }(), "the excerpt text")
        try expectVisiblyDifferent(
            base,
            {
                var c = base
                c.theme = .solarizedLight
                return c
            }(), "the syntax theme")
    }

    @Test func eachTemplateProducesADistinctComposition() throws {
        // The three templates lay the same content out differently, so each pair must
        // render visibly distinct pixels — a template that collapsed onto another would
        // be caught here.
        let content = SocialCardModel(
            title: "Headline", subtitle: "Subtitle", codeExcerpt: "let x = 1",
            author: "@jane", project: "vitrine", showLogo: true)
        let standard = {
            var c = content
            c.template = .standard
            return c
        }()
        let codeFocus = {
            var c = content
            c.template = .codeFocus
            return c
        }()
        let headline = {
            var c = content
            c.template = .headline
            return c
        }()
        try expectVisiblyDifferent(standard, codeFocus, "standard vs. code-focus layout")
        try expectVisiblyDifferent(standard, headline, "standard vs. headline layout")
        try expectVisiblyDifferent(codeFocus, headline, "code-focus vs. headline layout")
    }

    @Test func aTransparentBackgroundRendersDifferentlyFromASolidOne() throws {
        // The background is a rendered field too: the same card over transparent vs. a
        // solid color must differ, confirming the canvas background is composited.
        let base = SocialCardFixtures.defaultCard
        try expectVisiblyDifferent(
            {
                var c = base
                c.background = .solid(.white)
                return c
            }(),
            {
                var c = base
                c.background = .transparent
                return c
            }(),
            "the background style")
    }
}

// MARK: - Clipboard flow

@MainActor
@Suite("Social card clipboard flow (CS-041)")
struct SocialCardClipboardTests {
    @Test func copyPlacesAPNGOnThePasteboard() throws {
        // The clipboard flow writes a PNG representation a paste can consume.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = SocialCardRenderer.copyToPasteboard(SocialCardFixtures.defaultCard, scale: 1)
        #expect(copied)
        let data = try #require(pasteboard.data(forType: .png))
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }
}

// MARK: - Save & share flow refusal (CS-041 "clipboard, save, and share flows")

/// The save and share flows present modal AppKit UI on success, so a unit test
/// cannot drive a real save panel or share picker headlessly. What it *can* pin —
/// and what the acceptance turns on — is that both flows refuse an unrenderable
/// model *before* any UI is shown: `saveToFile` returns `.failed` and `share`
/// returns `false` while never touching the panel or `ShareManager`. That keeps
/// every entry point honest about an empty card without requiring a UI session.
@MainActor
@Suite("Social card save & share flows (CS-041)")
struct SocialCardSaveShareTests {
    @Test func saveRefusesAnEmptyModelBeforeShowingAPanel() {
        // `renderCGImage` returns nil for an empty model, so `saveToFile` short-
        // circuits to `.failed` before `NSSavePanel.runModal()` — no panel appears.
        #expect(SocialCardRenderer.saveToFile(SocialCardModel(), format: .png) == .failed)
        #expect(SocialCardRenderer.saveToFile(SocialCardModel(), format: .pdf) == .failed)
    }

    @Test func saveRefusesABlankHeadlineCardForBothFormats() {
        // A headline card carrying only an excerpt is unrenderable, so the save flow
        // must refuse it the same way for PNG and PDF.
        let blankHeadline = SocialCardModel(codeExcerpt: "let x = 1", template: .headline)
        #expect(SocialCardRenderer.saveToFile(blankHeadline, format: .png) == .failed)
        #expect(SocialCardRenderer.saveToFile(blankHeadline, format: .pdf) == .failed)
    }

    @Test func shareRefusesAnEmptyModelBeforePresentingThePicker() {
        // `share` returns false before reaching `ShareManager`, so a throwaway view is
        // never used to anchor a picker. No share sheet is presented.
        let anchor = NSView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(SocialCardRenderer.share(SocialCardModel(), relativeTo: anchor) == false)
        let blankHeadline = SocialCardModel(codeExcerpt: "let x = 1", template: .headline)
        #expect(SocialCardRenderer.share(blankHeadline, relativeTo: anchor) == false)
    }
}

// MARK: - Golden fixture (CS-041 "golden image fixture for default template")

/// Whether the social-card golden recorder is armed. Opt-in via
/// `VITRINE_RECORD_SOCIAL_CARD`, so a routine `make test` is read-only and never
/// rewrites the committed fixture.
enum SocialCardRecording {
    nonisolated static var isActive: Bool {
        guard let value = ProcessInfo.processInfo.environment["VITRINE_RECORD_SOCIAL_CARD"] else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }
}

@MainActor
@Suite("Social card golden fixture (CS-041)")
struct SocialCardGoldenTests {
    /// The committed manifest, or `nil` if none has been recorded yet.
    static let manifest = GoldenManifest.load(from: SocialCardGoldenPaths.fixturesDirectory)

    /// Whether the live runner matches the manifest's pinned image, gating the
    /// strict pixel comparison exactly like the CS-025 suite.
    static var isPinnedImage: Bool {
        guard let manifest else { return false }
        return manifest.pinnedImage == .current()
    }

    @Test func defaultTemplateMatchesGoldenOrRendersCleanly() throws {
        let card = SocialCardFixtures.defaultCard
        let image = try #require(
            SocialCardRenderer.renderCGImage(card, scale: 1),
            "render produced no image for the default social card")
        // The fixed-size card renders at a guaranteed 1200×630 on any runner.
        #expect(image.width == 1200 && image.height == 630)

        let goldenURL = SocialCardGoldenPaths.defaultFixtureURL
        let goldenExists = FileManager.default.fileExists(atPath: goldenURL.path)
        guard Self.isPinnedImage, goldenExists else {
            print(
                "SOCIAL CARD GOLDEN SKIP default-card "
                    + "(runner is not the pinned image or no fixture); render-only check passed")
            return
        }

        let golden = try #require(
            GoldenComparator.loadImage(at: goldenURL),
            "could not decode committed social-card golden")
        switch GoldenComparator.compare(golden, image) {
        case .success(let result):
            print(
                "SOCIAL CARD GOLDEN COMPARE default-card "
                    + "differing=\(result.differingPixels)/\(result.pixelCount) "
                    + "maxDelta=\(result.maxChannelDelta) "
                    + "fraction=\(String(format: "%.5f", result.differingFraction))")
            #expect(
                result.matches,
                """
                Social-card golden mismatch: \(result.differingPixels)/\(result.pixelCount) \
                pixels exceeded the per-channel tolerance (max channel delta \
                \(result.maxChannelDelta)).
                """)
        case .failure(let failure):
            Issue.record("Social-card golden comparison failed: \(failure)")
        }
    }

    @Test func committedFixtureAndManifestArePresentAndCurrent() throws {
        // The PNG and its manifest must travel together, and the recorded
        // fingerprint must match the live fixture, so a stale baseline is caught from
        // the manifest alone — before any pixel is compared.
        #expect(
            FileManager.default.fileExists(atPath: SocialCardGoldenPaths.defaultFixtureURL.path),
            "missing committed fixture \(SocialCardGoldenPaths.defaultFixtureName)")
        let manifest = try #require(
            Self.manifest, "Tests/Fixtures/SocialCards/manifest.json is missing or unparseable")
        #expect(manifest.schema == GoldenManifest.currentSchema)
        let record = try #require(
            manifest.scenarios["default-card"], "manifest is missing the default-card record")
        #expect(record.width == 1200 && record.height == 630)
        #expect(
            record.configFingerprint == SocialCardFixtures.defaultCard.fingerprint,
            "default-card config changed since recording; re-record the social-card fixture")
    }

    /// Records the default-template fixture and its manifest into the staging
    /// directory (CS-041). Opt-in: armed only by `VITRINE_RECORD_SOCIAL_CARD`, it
    /// stages into the sandbox-writable temp dir and prints the path, which is then
    /// copied into `Tests/Fixtures/SocialCards/` from outside the sandbox.
    @Test(
        .enabled(
            if: SocialCardRecording.isActive,
            "set VITRINE_RECORD_SOCIAL_CARD=1 to (re)generate the social-card fixture"))
    func recordDefaultFixture() throws {
        let directory = GoldenPaths.recordingOutputDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("vitrine-social-card-record", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("SOCIAL CARD OUTPUT \(directory.path)")

        let card = SocialCardFixtures.defaultCard
        let image = try #require(
            SocialCardRenderer.renderCGImage(card, scale: 1), "recording render failed")
        let png = try #require(ExportManager.pngData(from: image), "PNG encode failed")
        let pngURL = directory.appendingPathComponent(SocialCardGoldenPaths.defaultFixtureName)
        try png.write(to: pngURL)
        print("SOCIAL CARD RECORD default-card \(image.width)x\(image.height) \(pngURL.path)")

        let manifest = GoldenManifest(
            schema: GoldenManifest.currentSchema,
            pinnedImage: .current(),
            scenarios: [
                "default-card": GoldenManifest.ScenarioRecord(
                    width: image.width, height: image.height,
                    configFingerprint: card.fingerprint)
            ])
        try manifest.encoded().write(to: GoldenManifest.url(in: directory))
        print(
            "SOCIAL CARD RECORD manifest pinned to "
                + "\(manifest.pinnedImage.osVersion)/\(manifest.pinnedImage.architecture)/"
                + "swift\(manifest.pinnedImage.swiftVersion)")
    }
}
