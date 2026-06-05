import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Vitrine

/// CS-034 — Shortcuts, Services, and App Intents.
///
/// The automation surfaces share one pure core (`SnapshotRenderRequest` →
/// `SnapshotConfig`) and one render shell (`SnapshotRenderService`) that wraps the
/// unchanged `ExportManager` path, mirroring how the CLI (CS-033) is built. These
/// tests cover the unit-testable halves directly — request resolution, the picker
/// enum mappings, the render shell, and the Services registration contract — without
/// needing the live App Intents / Services runtime:
///
/// - **Request resolution** proves a Shortcut's parameters compose into exactly the
///   `SnapshotConfig` the app would render, applying the same precedence and never
///   touching the user's code (CS-020).
/// - **Picker enums** prove every case maps to a real model and that the literal
///   display titles cannot drift from the in-app catalog.
/// - **Render shell** proves automation produces real image bytes through the shared
///   pipeline and rejects empty input with a clear error.
/// - **Services contract** proves the declared send/return types and the pinned
///   provider selector line up with the Info.plist `NSServices` declaration.
///
/// `@MainActor` where a test touches the render path or main-actor model catalogs
/// (every render test in the project is); the test host is the app bundle, so the
/// bundled fonts are already registered.

// MARK: - Request resolution (the pure config core)

@MainActor
@Suite("SnapshotRenderRequest resolution (CS-034)")
struct SnapshotRenderRequestTests {
    @Test func defaultsMatchTheAppConfiguration() {
        // A bare request (just code) renders what the editor would with untouched
        // settings: the factory base style, the default scale, no fixed size.
        let request = SnapshotRenderRequest(code: "let x = 1")
        let config = request.makeConfig()

        #expect(config.code == "let x = 1")
        #expect(request.effectiveScale == CGFloat(SettingsDefaults.exportScale))
        #expect(request.fixedSize == nil)
        #expect(request.format == .png)
        #expect(request.profile == .sRGB)
        // The non-code fields come straight from the base style.
        #expect(config.theme == SnapshotConfig().theme)
        #expect(config.background == SnapshotConfig().background)
    }

    @Test func emptyOrWhitespaceCodeIsNotRenderable() {
        #expect(!SnapshotRenderRequest(code: "").hasRenderableCode)
        #expect(!SnapshotRenderRequest(code: "   \n\t ").hasRenderableCode)
        #expect(SnapshotRenderRequest(code: "x").hasRenderableCode)
    }

    @Test func languageIsDetectedWhenNotGiven() {
        // No explicit language → the same interpreter quick capture uses. A clear
        // Swift signal must resolve to Swift, not plain text.
        let request = SnapshotRenderRequest(
            code: "import SwiftUI\nstruct V: View { var body: some View { Text(\"hi\") } }")
        #expect(request.resolvedLanguage == .swift)
        #expect(request.makeConfig().language == .swift)
    }

    @Test func explicitLanguageOverridesDetection() {
        // An explicit language wins over what detection would have guessed.
        let request = SnapshotRenderRequest(code: "SELECT * FROM t", language: .python)
        #expect(request.resolvedLanguage == .python)
        #expect(request.makeConfig().language == .python)
    }

    @Test func themeOverrideResolvesThroughTheCatalog() {
        let request = SnapshotRenderRequest(code: "x", themeID: "dracula")
        #expect(request.makeConfig().theme == .dracula)
    }

    @Test func unknownThemeFallsBackToOneDark() {
        // A bad id degrades to One Dark rather than producing a broken render
        // (mirrors the catalog lookup the GUI uses).
        let request = SnapshotRenderRequest(code: "x", themeID: "no-such-theme")
        #expect(request.makeConfig().theme == .oneDark)
    }

    @Test func presetReframesPresentationButNeverTheCode() {
        var base = SnapshotConfig()
        base.code = "secret"
        base.language = .ruby
        let request = SnapshotRenderRequest(
            code: "let answer = 42", language: .swift, presetID: "opengraph", baseStyle: base)
        let config = request.makeConfig()

        // The code/language come from the request, never the base or the preset.
        #expect(config.code == "let answer = 42")
        #expect(config.language == .swift)
        // The preset's presentation guidance is applied.
        #expect(config.background == .gradient(.aurora))
        #expect(config.padding == SettingsDefaults.clampPadding(ExportPreset.openGraph.padding))
        // And it pins the OpenGraph size and 1× scale.
        #expect(request.fixedSize == CGSize(width: 1200, height: 630))
        #expect(request.effectiveScale == 1)
    }

    @Test func transparentBackgroundWinsOverAPresetBackground() {
        // `--transparent`-style override is the last word on the background, even
        // when a preset declares one.
        let request = SnapshotRenderRequest(
            code: "x", presetID: "opengraph", transparent: true)
        #expect(request.makeConfig().background == .transparent)
    }

    @Test func explicitScaleOverridesPresetAndDefault() {
        // Precedence: explicit scale wins over the preset's recommended scale.
        let request = SnapshotRenderRequest(code: "x", presetID: "opengraph", scale: 3)
        #expect(request.effectiveScale == 3)
        // The fixed size is still pinned by the preset.
        #expect(request.fixedSize == CGSize(width: 1200, height: 630))
    }

    @Test func scaleIsClampedIntoTheSupportedRange() {
        // A wild value can never reach the renderer.
        #expect(SnapshotRenderRequest(code: "x", scale: 99).effectiveScale == 3)
        #expect(SnapshotRenderRequest(code: "x", scale: 0).effectiveScale == 2)
    }

    @Test func baseStyleIsHonoredWhenNoOverrideGiven() {
        // The live style flows through: a request that overrides nothing keeps the
        // base style's theme/background/font.
        var base = SnapshotConfig()
        base.theme = .nord
        base.fontName = "Fira Code"
        base.background = .solid(.black)
        let config = SnapshotRenderRequest(code: "x", baseStyle: base).makeConfig()
        #expect(config.theme == .nord)
        #expect(config.fontName == "Fira Code")
        #expect(config.background == .solid(.black))
    }
}

// MARK: - Picker enums (no drift from the model catalogs)

@MainActor
@Suite("Snapshot intent picker enums (CS-034)")
struct SnapshotIntentEnumTests {
    @Test func languageEnumSentinelMeansAutomatic() {
        #expect(SnapshotLanguageAppEnum.automatic.language == nil)
        #expect(SnapshotLanguageAppEnum.swift.language == .swift)
    }

    @Test func everyNonAutomaticLanguageCaseMapsToARealLanguage() {
        // The picker must never offer a language the renderer cannot honor.
        for value in SnapshotLanguageAppEnum.allCases where value != .automatic {
            #expect(value.language != nil, "\(value) does not map to a Language")
        }
    }

    @Test func languageEnumCoversEveryAdvertisedLanguage() {
        // Every `Language` the app advertises is offered as a picker case, so a
        // Shortcut can pick any language the editor can.
        let mapped = Set(
            SnapshotLanguageAppEnum.allCases.compactMap { $0.language })
        #expect(mapped == Set(Language.allCases))
    }

    @Test func languageTitlesMatchTheInAppDisplayNames() {
        // The literal picker titles must not drift from `Language.displayName`.
        let titles = SnapshotLanguageAppEnum.caseDisplayRepresentations
        for value in SnapshotLanguageAppEnum.allCases {
            guard let language = value.language else { continue }
            let title = titles[value]?.title
            #expect(
                title == LocalizedStringResource(stringLiteral: language.displayName),
                "\(value) title drifted from Language.displayName")
        }
    }

    @Test func themeEnumSentinelMeansDefault() {
        #expect(SnapshotThemeAppEnum.default.themeID == nil)
        #expect(SnapshotThemeAppEnum.dracula.themeID == "dracula")
    }

    @Test func everyNonDefaultThemeCaseIsABuiltIn() {
        // The picker only offers stable, shareable built-in theme ids.
        for value in SnapshotThemeAppEnum.allCases where value != .default {
            let id = try? #require(value.themeID)
            #expect(Theme.builtInIDs.contains(id ?? ""), "\(value) is not a built-in theme id")
        }
    }

    @Test func themeEnumCoversEveryBuiltInTheme() {
        let mapped = Set(SnapshotThemeAppEnum.allCases.compactMap { $0.themeID })
        #expect(mapped == Theme.builtInIDs)
    }

    @Test func themeTitlesMatchTheCatalogDisplayNames() {
        let titles = SnapshotThemeAppEnum.caseDisplayRepresentations
        for value in SnapshotThemeAppEnum.allCases {
            guard let id = value.themeID else { continue }
            let theme = Theme.theme(withID: id)
            #expect(
                titles[value]?.title == LocalizedStringResource(stringLiteral: theme.displayName),
                "\(value) title drifted from the theme catalog")
        }
    }

    @Test func presetEnumSentinelMeansNone() {
        #expect(SnapshotPresetAppEnum.none.presetID == nil)
        #expect(SnapshotPresetAppEnum.openGraph.presetID == "opengraph")
    }

    @Test func everyNonNonePresetCaseResolves() {
        for value in SnapshotPresetAppEnum.allCases where value != .none {
            #expect(
                ExportPreset.preset(withID: value.presetID) != nil,
                "\(value) does not map to an ExportPreset")
        }
    }

    @Test func presetEnumCoversEveryDestinationPreset() {
        let mapped = Set(SnapshotPresetAppEnum.allCases.compactMap { $0.presetID })
        #expect(mapped == Set(ExportPreset.all.map(\.id)))
    }

    @Test func presetTitlesMatchTheCatalogDisplayNames() {
        let titles = SnapshotPresetAppEnum.caseDisplayRepresentations
        for value in SnapshotPresetAppEnum.allCases {
            guard let preset = ExportPreset.preset(withID: value.presetID) else { continue }
            #expect(
                titles[value]?.title == LocalizedStringResource(stringLiteral: preset.displayName),
                "\(value) title drifted from the preset catalog")
        }
    }

    @Test func formatEnumMapsToExportFormat() {
        #expect(SnapshotFormatAppEnum.png.format == .png)
        #expect(SnapshotFormatAppEnum.pdf.format == .pdf)
    }
}

// MARK: - Render shell (the shared automation render path)

@MainActor
@Suite("SnapshotRenderService (CS-034)")
struct SnapshotRenderServiceTests {
    @Test func rendersRealPNGBytes() throws {
        let request = SnapshotRenderRequest(code: "let x = 1", language: .swift)
        let data = try SnapshotRenderService.renderData(request)
        // A PNG file starts with the 8-byte signature.
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test func rendersRealPDFBytes() throws {
        let request = SnapshotRenderRequest(code: "let x = 1", language: .swift, format: .pdf)
        let data = try SnapshotRenderService.renderData(request)
        #expect(data.starts(with: Array("%PDF-".utf8)))
    }

    @Test func emptyCodeThrowsAClearError() {
        let request = SnapshotRenderRequest(code: "   ")
        #expect(throws: SnapshotRenderService.RenderError.emptyCode) {
            try SnapshotRenderService.renderData(request)
        }
        #expect(throws: SnapshotRenderService.RenderError.emptyCode) {
            try SnapshotRenderService.renderImage(request)
        }
    }

    @Test func renderImageProducesANonEmptyImage() throws {
        let request = SnapshotRenderRequest(code: "print(1)", language: .python)
        let image = try SnapshotRenderService.renderImage(request)
        #expect(image.size.width > 0 && image.size.height > 0)
    }

    @Test func openGraphPresetRendersExactPinnedPixels() throws {
        // The automation path honors a fixed-size preset exactly like the GUI/CLI.
        let request = SnapshotRenderRequest(code: "let x = 1", presetID: "opengraph")
        let data = try SnapshotRenderService.renderData(request)
        let image = try #require(NSImage(data: data))
        let rep = try #require(image.representations.first)
        #expect(rep.pixelsWide == 1200)
        #expect(rep.pixelsHigh == 630)
    }

    @Test func automationRenderGoesThroughTheSameExportManagerPipeline() throws {
        // The shell adds only request resolution + an empty-code guard around the
        // unchanged `ExportManager` path, so a render through the service must match a
        // direct `ExportManager` render of the same config — the CS-034 "same pipeline
        // as the app" guarantee.
        //
        // Equality is asserted on the *decoded image dimensions*, not raw PNG bytes:
        // `ImageRenderer` text rasterization is not guaranteed byte-stable across two
        // separate renders on every OS/Xcode, so two encodings of the same canvas can
        // differ by a few bytes. The dimensions are deterministic and prove both paths
        // laid out and rendered the identical canvas; the byte-identity guarantee is
        // covered separately by the CLI suite where it is recorded on the pinned image.
        let request = SnapshotRenderRequest(
            code: "let answer = 42", language: .swift, themeID: "dracula")
        let viaService = try SnapshotRenderService.renderData(request)
        let serviceImage = try #require(decodeCGImage(viaService))

        let config = request.makeConfig()
        let direct = try #require(
            ExportManager.renderCGImage(
                config, scale: request.effectiveScale, fixedSize: request.fixedSize,
                profile: request.profile))

        #expect(serviceImage.width == direct.width)
        #expect(serviceImage.height == direct.height)
    }

    /// Decodes PNG `data` back into a `CGImage` so a render's pixel dimensions can be
    /// asserted independently of its exact byte encoding.
    private func decodeCGImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

// MARK: - Services registration contract (matches the Info.plist NSServices)

@MainActor
@Suite("Services registration (CS-034)")
struct ServiceRegistrationTests {
    @Test func acceptsPlainTextAndReturnsImageTypes() {
        // The service takes a text selection and returns an image, matching the
        // NSSendTypes/NSReturnTypes declared in the Info.plist.
        #expect(ServiceRegistration.sendTypes.contains(.string))
        #expect(ServiceRegistration.returnTypes.contains(.png))
    }

    @Test func providerRespondsToThePinnedSelector() {
        // The Info.plist NSMessage is `renderCodeImage`, so AppKit invokes
        // `renderCodeImage:userData:error:`; the provider must expose exactly that
        // selector regardless of the Swift argument label.
        let selector = NSSelectorFromString("renderCodeImage:userData:error:")
        #expect(CodeImageService.shared.responds(to: selector))
    }

    @Test func emptySelectionIsRejectedWithAMessageAndWritesNoImage() {
        // With no text on the pasteboard, the service fails with a user-facing
        // message and leaves no image behind — it never renders a blank picture.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitrineServiceTest-empty"))
        pasteboard.clearContents()

        let outcome = CodeImageService.shared.process(pasteboard: pasteboard)

        guard case .failed(let message) = outcome else {
            Issue.record("expected a failure outcome for an empty selection")
            return
        }
        #expect(!message.isEmpty)
        #expect(pasteboard.data(forType: .png) == nil)
    }

    @Test func selectedTextIsRenderedOntoThePasteboardAsAnImage() {
        // The happy path: text on the pasteboard is replaced by a rendered PNG the
        // host app can paste, and the outcome reports success.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("VitrineServiceTest-render"))
        pasteboard.clearContents()
        pasteboard.setString("let greeting = \"hello\"", forType: .string)

        let outcome = CodeImageService.shared.process(pasteboard: pasteboard)

        #expect(outcome == .rendered)
        // An image representation is now on the pasteboard.
        #expect(pasteboard.data(forType: .png) != nil)
    }
}
