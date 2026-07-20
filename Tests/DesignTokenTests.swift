import AppKit
import SwiftUI
import Testing

@testable import Vitrine

/// Token availability + monotonic scale checks for the design system.
@MainActor
@Suite("Design tokens")
struct DesignTokenTests {
    @Test func spacingScaleIsMonotonicAndPositive() {
        let scale = [
            Brand.Spacing.xxs, Brand.Spacing.xs, Brand.Spacing.sm, Brand.Spacing.md,
            Brand.Spacing.lg, Brand.Spacing.xl, Brand.Spacing.xxl,
        ]
        #expect(scale.first == 4)
        #expect(scale.allSatisfy { $0 > 0 })
        #expect(zip(scale, scale.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func radiusScaleIsMonotonic() {
        let scale = [Brand.Radius.sm, Brand.Radius.md, Brand.Radius.lg, Brand.Radius.xl]
        #expect(zip(scale, scale.dropFirst()).allSatisfy { $0 < $1 })
        // The card radius matches the SnapshotConfig default so the preview and
        // export stay in sync. Compare as Double across the CGFloat boundary.
        #expect(SnapshotConfig().cornerRadius == Double(Brand.Radius.card))
    }

    @Test func shadowRecipesAreAvailable() {
        #expect(Brand.Shadow.card.radius > 0)
        #expect(Brand.Shadow.elevated.radius > Brand.Shadow.card.radius)
        // The elevated recipe drives the default export shadow radius.
        #expect(SnapshotConfig().shadowRadius == Double(Brand.Shadow.elevated.radius))
    }

    @Test func strokeWidthsAreHairline() {
        #expect(Brand.Stroke.hairline == 1)
        #expect(Brand.Stroke.focus > Brand.Stroke.hairline)
    }

    @Test func systemAccentOverrideReflectsTheAppleAccentColorValue() {
        // Absent key (nil) = the default "Multicolor": keep Vitrine's brand accent.
        #expect(!VitrineTokens.Accent.usesSystemAccentOverride(accentColorValue: nil))
        // A specific accent picked in System Settings (3 = Green): follow it.
        #expect(VitrineTokens.Accent.usesSystemAccentOverride(accentColorValue: 3))
        // Graphite is stored as -1 — still a deliberate, non-Multicolor choice.
        #expect(VitrineTokens.Accent.usesSystemAccentOverride(accentColorValue: -1))
    }
}

/// The app UI and exported presets must share one brand vocabulary.
@MainActor
@Suite("Brand vocabulary")
struct BrandVocabularyTests {
    /// Resolves a SwiftUI `Color` to sRGB components for comparison.
    private func rgb(_ color: Color) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let ns = try #require(NSColor(color).usingColorSpace(.sRGB))
        return (ns.redComponent, ns.greenComponent, ns.blueComponent)
    }

    @Test func auroraPresetUsesBrandAccentColors() throws {
        let stops = GradientPreset.aurora.colors
        #expect(stops.count == 2)
        // Both stops must come from the brand palette so the signature export
        // preset and the app chrome speak the same violet→azure vocabulary: the
        // near stop is the primary accent, the far stop the secondary accent.
        let first = try rgb(stops[0])
        let accent = try rgb(Brand.Palette.accent.light)
        #expect(abs(first.r - accent.r) < 0.01)
        #expect(abs(first.g - accent.g) < 0.01)
        #expect(abs(first.b - accent.b) < 0.01)

        let second = try rgb(stops[1])
        let accentSecondary = try rgb(Brand.Palette.accentSecondary.light)
        #expect(abs(second.r - accentSecondary.r) < 0.01)
        #expect(abs(second.g - accentSecondary.g) < 0.01)
        #expect(abs(second.b - accentSecondary.b) < 0.01)
    }

    @Test func auroraIsTheDefaultBackground() {
        #expect(SnapshotConfig().background == .gradient(.aurora))
    }

    @Test func brandSymbolIsSharedByMenuBarAndMarks() {
        // A single symbol name backs both the menu-bar extra and the BrandMark,
        // so the identity can never drift between surfaces.
        #expect(!Brand.symbolName.isEmpty)
        #expect(Brand.symbolName == "camera.viewfinder")
    }
}

/// Every brand color must produce a concrete value in light, dark, and both
/// high-contrast appearances.
@MainActor
@Suite("Palette appearances")
struct PaletteAppearanceTests {
    /// All semantic brand colors, keyed by name for readable failures. Built
    /// inside the test (which is `@MainActor`) so accessing the palette stays on
    /// the main actor under Swift 6 isolation.
    private var palette: [(String, Brand.BrandColor)] {
        [
            ("accent", Brand.Palette.accent),
            ("accentSecondary", Brand.Palette.accentSecondary),
            ("stage", Brand.Palette.stage),
            ("textPrimary", Brand.Palette.textPrimary),
            ("textSecondary", Brand.Palette.textSecondary),
            ("border", Brand.Palette.border),
        ]
    }

    @Test func everyColorResolvesInEveryAppearance() throws {
        for (name, brand) in palette {
            for scheme in [ColorScheme.light, .dark] {
                for highContrast in [false, true] {
                    let resolved = brand.resolved(scheme: scheme, highContrast: highContrast)
                    // Resolving to a concrete NSColor proves the variant exists.
                    let ns = NSColor(resolved).usingColorSpace(.sRGB)
                    #expect(ns != nil, "\(name) failed to resolve in \(scheme)/\(highContrast)")
                }
            }
        }
    }

    /// `resolved(scheme:highContrast:)` is the load-bearing mapping every brand
    /// color flows through, so each of the four appearance cases must return its
    /// *own* declared variant — not merely some non-nil color. A bug that swapped
    /// two cases (e.g. returned `dark` for `.light`) would still resolve to a
    /// valid color and slip past the existence check above; building a color with
    /// four deliberately distinct stored variants and matching them by identity
    /// pins the switch arms down exactly.
    @Test func resolvedReturnsTheVariantForEachAppearance() {
        let probe = Brand.BrandColor(
            light: .red,
            dark: .green,
            lightHighContrast: .blue,
            darkHighContrast: .yellow
        )
        #expect(probe.resolved(scheme: .light, highContrast: false) == .red)
        #expect(probe.resolved(scheme: .dark, highContrast: false) == .green)
        #expect(probe.resolved(scheme: .light, highContrast: true) == .blue)
        #expect(probe.resolved(scheme: .dark, highContrast: true) == .yellow)
    }

    /// The initializer documents that omitting a high-contrast variant falls back
    /// to the matching base appearance. Verify that contract directly so the
    /// default is not silently changed to, say, the light value in both schemes.
    @Test func highContrastVariantsDefaultToBaseAppearance() {
        let fallback = Brand.BrandColor(light: .red, dark: .green)
        #expect(fallback.resolved(scheme: .light, highContrast: true) == .red)
        #expect(fallback.resolved(scheme: .dark, highContrast: true) == .green)
    }
}

/// WCAG contrast checks for the critical text/background pairs.
@MainActor
@Suite("Contrast")
struct ContrastTests {
    /// Primary text on the neutral stage must clear AA for body text in every
    /// appearance, including high contrast.
    @Test(arguments: [
        (ColorScheme.light, false), (.light, true), (.dark, false), (.dark, true),
    ])
    func primaryTextOnStageMeetsAA(_ scheme: ColorScheme, _ highContrast: Bool) {
        let text = Brand.Palette.textPrimary.resolved(scheme: scheme, highContrast: highContrast)
        let bg = Brand.Palette.stage.resolved(scheme: scheme, highContrast: highContrast)
        let ratio = Brand.Contrast.ratio(text, on: bg)
        #expect(
            ratio >= Brand.Contrast.aaNormal,
            "primary text contrast \(ratio) below AA in \(scheme)/\(highContrast)")
    }

    /// Secondary text is allowed the large-text threshold but must still be
    /// comfortably legible on the stage.
    @Test(arguments: [
        (ColorScheme.light, false), (.light, true), (.dark, false), (.dark, true),
    ])
    func secondaryTextOnStageMeetsLargeTextAA(_ scheme: ColorScheme, _ highContrast: Bool) {
        let text = Brand.Palette.textSecondary.resolved(scheme: scheme, highContrast: highContrast)
        let bg = Brand.Palette.stage.resolved(scheme: scheme, highContrast: highContrast)
        let ratio = Brand.Contrast.ratio(text, on: bg)
        #expect(
            ratio >= Brand.Contrast.aaLarge,
            "secondary text contrast \(ratio) below AA-large in \(scheme)/\(highContrast)")
    }

    @Test func highContrastImprovesPrimaryTextRatio() {
        let stageLight = Brand.Palette.stage
        let textLight = Brand.Palette.textPrimary
        let normal = Brand.Contrast.ratio(
            textLight.resolved(scheme: .light, highContrast: false),
            on: stageLight.resolved(scheme: .light, highContrast: false))
        let high = Brand.Contrast.ratio(
            textLight.resolved(scheme: .light, highContrast: true),
            on: stageLight.resolved(scheme: .light, highContrast: true))
        #expect(high >= normal)
    }

    @Test func contrastRatioIsSymmetricAndBounded() {
        let white = Color.white
        let black = Color.black
        let ratio = Brand.Contrast.ratio(white, on: black)
        // Pure black on white is the maximum WCAG ratio of 21:1.
        #expect(abs(ratio - 21) < 0.2)
        #expect(abs(ratio - Brand.Contrast.ratio(black, on: white)) < 0.001)
        #expect(abs(Brand.Contrast.ratio(white, on: white) - 1) < 0.001)
    }
}

/// The accent and stage colors live twice — in code (`Brand.Palette`) and in the
/// asset catalog (`AccentColor`/`BrandStage`). DESIGN-SYSTEM.md promises they are
/// mirrored across the same four variants, so this asserts the catalog cannot
/// silently drift from the code palette.
///
/// The catalog's source-of-truth `Contents.json` declares sRGB components per
/// appearance. We compare those declared values directly to the code palette's
/// resolved colors. (Resolving the *compiled* catalog color at runtime cannot
/// reach the high-contrast variants from a unit test: the increased-contrast
/// entry is gated behind the live system accessibility setting, not the
/// `NSAppearance` name — which is exactly why the code palette exists as the
/// testable source.)
@MainActor
@Suite("Asset catalog parity")
struct AssetCatalogParityTests {
    /// One appearance variant: how the colorset JSON tags it, and the matching
    /// `BrandColor` accessor.
    private struct Variant {
        let label: String
        let luminosity: String?  // "dark" for dark entries, nil otherwise.
        let highContrast: Bool
        let scheme: ColorScheme
    }

    private static let variants: [Variant] = [
        Variant(label: "light", luminosity: nil, highContrast: false, scheme: .light),
        Variant(label: "dark", luminosity: "dark", highContrast: false, scheme: .dark),
        Variant(label: "lightHC", luminosity: nil, highContrast: true, scheme: .light),
        Variant(label: "darkHC", luminosity: "dark", highContrast: true, scheme: .dark),
    ]

    // MARK: Colorset JSON decoding

    private struct ColorSet: Decodable {
        let colors: [Entry]
    }

    private struct Entry: Decodable {
        let appearances: [Appearance]?
        let color: ColorBody
    }

    private struct Appearance: Decodable {
        let appearance: String
        let value: String
    }

    private struct ColorBody: Decodable {
        let components: Components
    }

    private struct Components: Decodable {
        let red: String
        let green: String
        let blue: String
    }

    /// The `Assets.xcassets` directory, located relative to this test file so
    /// the check reads the source-of-truth JSON regardless of bundle packaging.
    private static var assetsDirectory: URL {
        // .../vitrine/Tests/DesignTokenTests.swift → .../vitrine
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        return
            repoRoot
            .appendingPathComponent("Vitrine")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Assets.xcassets")
    }

    /// Decodes the components of a colorset for a specific appearance variant.
    private func components(
        ofColorset name: String, variant: Variant
    ) throws -> (r: Double, g: Double, b: Double) {
        let url =
            Self.assetsDirectory
            .appendingPathComponent("\(name).colorset")
            .appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: url)
        let set = try JSONDecoder().decode(ColorSet.self, from: data)

        let entry = try #require(
            set.colors.first { entry in
                let appearances = entry.appearances ?? []
                let luminosityMatches =
                    appearances.contains { $0.appearance == "luminosity" }
                    ? appearances.contains {
                        $0.appearance == "luminosity" && $0.value == variant.luminosity
                    }
                    : variant.luminosity == nil
                let contrastPresent = appearances.contains { $0.appearance == "contrast" }
                return luminosityMatches && contrastPresent == variant.highContrast
            },
            "\(name).colorset has no entry for \(variant.label)")

        let c = entry.color.components
        return (
            r: try parse(c.red), g: try parse(c.green), b: try parse(c.blue)
        )
    }

    /// Parses a colorset component string (decimal `"0.310"` or hex `"0xFF"`).
    private func parse(_ raw: String) throws -> Double {
        if raw.hasPrefix("0x") {
            let value = try #require(UInt8(raw.dropFirst(2), radix: 16))
            return Double(value) / 255
        }
        return try #require(Double(raw))
    }

    /// sRGB components of a code-palette variant.
    private func components(of color: Color) throws -> (r: Double, g: Double, b: Double) {
        let srgb = try #require(NSColor(color).usingColorSpace(.sRGB))
        return (Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent))
    }

    /// Asserts every appearance variant of an asset color matches the code
    /// palette within a tolerance that absorbs the catalog's 3-decimal rounding.
    private func expectParity(
        colorset name: String, palette: Brand.BrandColor
    ) throws {
        for variant in Self.variants {
            let asset = try components(ofColorset: name, variant: variant)
            let code = try components(
                of: palette.resolved(scheme: variant.scheme, highContrast: variant.highContrast))
            let tolerance = 0.01
            #expect(
                abs(asset.r - code.r) < tolerance,
                "\(name) red drift in \(variant.label): \(asset.r) vs \(code.r)")
            #expect(
                abs(asset.g - code.g) < tolerance,
                "\(name) green drift in \(variant.label): \(asset.g) vs \(code.g)")
            #expect(
                abs(asset.b - code.b) < tolerance,
                "\(name) blue drift in \(variant.label): \(asset.b) vs \(code.b)")
        }
    }

    @Test func accentColorMatchesCodePalette() throws {
        try expectParity(colorset: "AccentColor", palette: Brand.Palette.accent)
    }

    @Test func brandStageMatchesCodePalette() throws {
        try expectParity(colorset: "BrandStage", palette: Brand.Palette.stage)
    }
}
