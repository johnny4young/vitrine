import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing

@testable import Vitrine

// `import SwiftUI` also brings a `BackgroundStyle` (a `ShapeStyle`) into scope, so
// the unqualified name is ambiguous here. Pin it to the app's canvas-background
// model for this file, matching `BackgroundTests`.
private typealias BackgroundStyle = Vitrine.BackgroundStyle

/// The launch-gallery catalog and its design-QA suite.
///
/// ## What this is
///
/// A screenshot app should ship with *evidence* of its visual quality, not rely on
/// subjective memory. This file is the **single source of truth** for the launch
/// gallery: a deterministic set of representative code screenshots — across
/// languages, themes, transparent backgrounds, social presets, and a verified
/// high-contrast/accessibility pairing — rendered through the **unchanged**
/// production export path (`ExportManager.renderCGImage`). The same images are
/// generated for README/release notes and committed under `Tests/Fixtures/Samples/`,
/// so design review compares against generated artifacts instead of hand-made
/// mockups.
///
/// ## The three jobs of this suite
///
/// Mirroring the golden-image architecture, one catalog feeds three
/// consumers so a sample can never drift between them:
///
/// 1. **Render regression (always on).** `SampleGalleryTests.everySampleRenders`
///    renders every catalog entry on any machine and fails if the pipeline ever
///    stops producing an image, so a routine `make test` exercises the full set
///    end to end.
/// 2. **Generator (opt-in).** `SampleGalleryGeneratorTests` is armed only by
///    `VITRINE_GENERATE_GALLERY=1` (via `make gallery` →
///    `scripts/generate-launch-gallery.swift`). It stages the PNGs plus a
///    `manifest.json` in the sandboxed host's container temp and prints the
///    staging path on one `GALLERY OUTPUT <path>` line, which the script copies
///    into `Tests/Fixtures/Samples/`.
/// 3. **Artifact presence (always on, once committed).** `SampleArtifactTests`
///    asserts the committed fixtures and manifest exist and stay in sync with the
///    catalog, so a dropped or stale sample is caught in CI.
///
/// Keeping the recorder isolated from the artifact checks means the suite can never
/// "fix" a missing artifact by silently regenerating it; that is always a reviewed,
/// explicit `make gallery` step.
enum SampleGallery {
    /// One representative screenshot in the launch gallery.
    ///
    /// A sample is fully deterministic: every pixel-affecting field of its
    /// `SnapshotConfig` and the render `scale` are pinned, so the bytes generated
    /// for the committed fixture and the bytes re-rendered by the regression suite
    /// come from identical input on a given OS/Xcode image.
    struct Sample: Identifiable, Sendable {
        /// Stable slug used for the PNG file name and the manifest key
        /// (e.g. `lang-python`, `theme-dracula`, `preset-opengraph`).
        let id: String
        /// The category this sample belongs to, used to group the gallery in docs
        /// and to assert coverage of every required surface.
        let category: Category
        /// A short, human-readable caption shown in the gallery doc.
        let caption: String
        /// The render scale (resolution multiplier). Content samples use the app's
        /// default 2× look; a fixed-size preset (OpenGraph) pins 1× so its logical
        /// and pixel sizes match.
        let scale: CGFloat
        /// The exact logical canvas size to render, when this sample pins one (the
        /// OpenGraph preset's 1200×630); `nil` lets the canvas hug its content. Held
        /// on the sample so every consumer renders identical input without re-deriving
        /// it from the slug.
        let fixedSize: CGSize?
        /// The exact configuration rendered. Captured by value so the catalog is the
        /// only place a sample's look is defined.
        let config: SnapshotConfig

        /// The PNG file name for this sample under `Tests/Fixtures/Samples/`.
        var fileName: String { "\(id).png" }

        init(
            id: String, category: Category, caption: String, scale: CGFloat,
            fixedSize: CGSize? = nil, config: SnapshotConfig
        ) {
            self.id = id
            self.category = category
            self.caption = caption
            self.scale = scale
            self.fixedSize = fixedSize
            self.config = config
        }
    }

    /// The visual surface a sample exercises. Every case in `Category.allCases`
    /// must be represented by at least one sample (asserted by the suite), so the
    /// gallery provably covers the documented coverage: languages, themes, transparent
    /// backgrounds, social presets, and accessibility/high-contrast states.
    enum Category: String, CaseIterable, Sendable {
        case language
        case theme
        case preset
        case transparent
        case accessibility

        /// A human heading for the gallery doc.
        var heading: String {
            switch self {
            case .language: "Languages"
            case .theme: "Themes"
            case .preset: "Social & export presets"
            case .transparent: "Transparent backgrounds"
            case .accessibility: "Accessibility / high contrast"
            }
        }
    }

    // MARK: Sample source code

    /// A compact, idiomatic Swift snippet used wherever the *style* (theme, preset,
    /// transparency) is what a sample demonstrates, so the only variable is the look.
    /// Small enough to keep committed PNGs tiny, varied enough to exercise keyword,
    /// type, string, number, and comment colors.
    static let swiftSample = """
        import SwiftUI

        struct CounterView: View {
            // A tiny stateful view.
            @State private var count = 0

            var body: some View {
                Button("Tapped \\(count) times") {
                    count += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
        """

    /// One short, idiomatic snippet per language sample, so the languages gallery
    /// shows real highlighting for each rather than the same Swift over and over.
    static let languageSnippets: [Language: String] = [
        .python:
            "def greet(name: str) -> str:\n    # Build a friendly greeting.\n    return f\"Hello, {name}!\"",
        .typescript:
            "const add = (a: number, b: number): number => {\n  return a + b; // sum two numbers\n};",
        .go:
            "package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"hi\") // say hello\n}",
        .rust:
            "fn main() {\n    let nums = [1, 2, 3];\n    let sum: i32 = nums.iter().sum();\n    println!(\"{sum}\");\n}",
        .sql:
            "SELECT id, name\nFROM users\nWHERE active = TRUE\nORDER BY name;",
    ]

    // MARK: The catalog

    /// Every launch-gallery sample, in gallery order: languages, themes, presets,
    /// transparent backgrounds, then the accessibility/high-contrast pairing.
    ///
    /// This is the catalog every consumer reads. Adding a sample here automatically
    /// flows it into the render regression, the generator, the manifest, and the
    /// artifact-presence checks — one place, no duplication ("adding a
    /// sample is a one-file change").
    static let all: [Sample] =
        languageSamples + themeSamples + presetSamples
        + transparentSamples + accessibilitySamples

    /// Looks up a sample by its slug id, for targeted assertions.
    static func sample(withID id: String) -> Sample? {
        all.first { $0.id == id }
    }

    // MARK: Category builders

    /// One sample per language in `languageSnippets`, each on a complementary theme
    /// so the languages row reads as a varied, real gallery.
    private static var languageSamples: [Sample] {
        let pairing: [Language: (Theme, BackgroundStyle)] = [
            .python: (.dracula, .gradient(.night)),
            .typescript: (.nightOwl, .gradient(.ocean)),
            .go: (.oneDark, .gradient(.aurora)),
            .rust: (.gruvbox, .gradient(.sunset)),
            .sql: (.tokyoNight, .gradient(.forest)),
        ]
        // Sort by display name so the catalog order is stable regardless of the
        // dictionary's iteration order.
        return languageSnippets.keys
            .sorted { $0.displayName < $1.displayName }
            .map { language in
                let (theme, background) = pairing[language] ?? (.oneDark, .gradient(.aurora))
                var config = SnapshotConfig()
                config.code = languageSnippets[language] ?? swiftSample
                config.language = language
                config.theme = theme
                config.background = background
                return Sample(
                    id: "lang-\(language.rawValue)",
                    category: .language,
                    caption: "\(language.displayName) on \(theme.displayName)",
                    scale: 2,
                    config: config)
            }
    }

    /// One sample per built-in theme over the same Swift snippet, so the themes row
    /// isolates the syntax palette as the only variable.
    private static var themeSamples: [Sample] {
        Theme.builtIns.map { theme in
            var config = SnapshotConfig()
            config.code = swiftSample
            config.language = .swift
            config.theme = theme
            return Sample(
                id: "theme-\(theme.id)",
                category: .theme,
                caption: "\(theme.displayName) theme",
                scale: 2,
                config: config)
        }
    }

    /// One sample per export/social preset applied to the signature theme,
    /// so the gallery shows the framed output a user actually shares to each surface.
    /// The fixed-size OpenGraph preset renders at its pinned 1× so the committed
    /// fixture is exactly 1200×630.
    private static var presetSamples: [Sample] {
        ExportPreset.all.map { preset in
            var config = SnapshotConfig()
            config.code = swiftSample
            config.language = .swift
            preset.apply(to: &config)
            return Sample(
                id: "preset-\(preset.id)",
                category: .preset,
                caption: preset.displayName,
                scale: CGFloat(preset.scale),
                fixedSize: preset.sizing.fixedSize,
                config: config)
        }
    }

    /// Transparent-background samples — the load-bearing real-alpha case.
    /// Both a dark and a light theme are shown so the gallery proves the corners
    /// stay clear regardless of the code card's luminance.
    private static var transparentSamples: [Sample] {
        let pairings: [(suffix: String, theme: Theme, caption: String)] = [
            ("dark", .oneDark, "Transparent canvas (dark code card)"),
            ("light", .github, "Transparent canvas (light code card)"),
        ]
        return pairings.map { pairing in
            var config = SnapshotConfig()
            config.code = swiftSample
            config.language = .swift
            config.theme = pairing.theme
            config.background = .transparent
            return Sample(
                id: "transparent-\(pairing.suffix)",
                category: .transparent,
                caption: pairing.caption,
                scale: 2,
                config: config)
        }
    }

    /// The accessibility / high-contrast sample ("...and accessibility/
    /// high-contrast states when implemented").
    ///
    /// The rendered code image takes its contrast from the chosen theme — there is
    /// no separate high-contrast *render mode* — so this sample uses a curated,
    /// **WCAG-AA-verified** high-contrast custom palette (`highContrastPalette`).
    /// Because that palette's colors are value-typed and Swift-accessible, the suite
    /// can assert the text-on-card contrast statically (unlike a built-in theme,
    /// whose syntax colors only exist inside Highlightr at render time). A solid,
    /// dark canvas keeps the focus on the code card's legibility.
    private static var accessibilitySamples: [Sample] {
        var config = SnapshotConfig()
        config.code = swiftSample
        config.language = .swift
        config.theme = highContrastTheme
        config.fontSize = 15
        config.background = .solid(RGBAColor(Color(red: 0.04, green: 0.05, blue: 0.08)))
        return [
            Sample(
                id: "a11y-high-contrast",
                category: .accessibility,
                caption: "High-contrast palette (WCAG AA verified)",
                scale: 2,
                config: config)
        ]
    }

    /// A curated high-contrast syntax palette whose foreground/background and each
    /// token color clear the WCAG AA normal-text threshold against the card
    /// background. Used by the accessibility sample and asserted in the suite.
    static let highContrastPalette = ThemePalette(
        background: hex("#0B0E14"),
        foreground: hex("#FFFFFF"),
        keyword: hex("#FF9E64"),
        string: hex("#9ECE6A"),
        comment: hex("#A9B1D6"),
        number: hex("#7DCFFF"),
        type: hex("#73DACA"),
        function: hex("#7AA2F7"),
        variable: hex("#E0E0E0"),
        attribute: hex("#BB9AF7"))

    /// Parses a compile-time-constant hex string into a `HexColor`, trapping on a
    /// malformed literal. `HexColor("…")` is failable for untrusted input; the
    /// palette above uses only known-valid literals, so a non-optional helper keeps
    /// it readable while still surfacing a typo loudly (a crash in this test file,
    /// never in the app).
    private static func hex(_ string: String) -> HexColor {
        guard let color = HexColor(string) else {
            preconditionFailure("invalid hex literal in the gallery palette: \(string)")
        }
        return color
    }

    /// The custom theme backing the accessibility sample, built from
    /// `highContrastPalette`.
    static let highContrastTheme = Theme(
        id: "a11y-high-contrast",
        displayName: "High Contrast",
        palette: highContrastPalette)

    // MARK: Manifest fingerprint

    /// A stable, content-derived fingerprint of a sample's deterministic config and
    /// render parameters, recorded in the manifest.
    ///
    /// It is a SHA-256 over the pixel-affecting fields, so any input change that
    /// would invalidate a committed PNG also changes the fingerprint — letting the
    /// artifact suite detect a stale fixture from the manifest alone, before
    /// comparing a single pixel. It carries no PII: only the background's
    /// non-PII `diagnosticsKind`, never an image path.
    static func fingerprint(for sample: Sample) -> String {
        let c = sample.config
        let highlight = LineHighlight.normalize(c.highlightedLineRanges)
            .map { "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: ",")
        let descriptor = [
            "id=\(sample.id)",
            "code=\(c.code)",
            "language=\(c.language.rawValue)",
            "theme=\(c.theme.id)",
            "font=\(c.fontName)@\(c.fontSize)",
            "ligatures=\(c.fontLigatures)",
            "padding=\(c.padding)",
            "corner=\(c.cornerRadius)",
            "chrome=\(c.showChrome)",
            "shadow=\(c.showShadow)",
            "lineNumbers=\(c.showLineNumbers)",
            "highlight=[\(highlight)]",
            "background=\(c.background.diagnosticsKind)",
            "scale=\(Int(sample.scale))",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(descriptor.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Paths

/// Locates the committed launch-gallery directory in the source tree.
///
/// Like the golden fixtures, the test bundle runs from a built product, so
/// the gallery is anchored to this source file via `#filePath`: the generator stages
/// images and the artifact suite reads them from the same `Tests/Fixtures/Samples/`.
enum SampleGalleryPaths {
    /// The absolute path to the committed gallery directory
    /// (`<repo>/Tests/Fixtures/Samples/`), derived from this file's location.
    static var fixturesDirectory: URL {
        // #filePath → <repo>/Tests/SampleGallery.swift; drop the file name to reach
        // <repo>/Tests, then descend into Fixtures/Samples.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("Samples", isDirectory: true)
    }

    /// Where the generator *writes* the staged images and manifest.
    ///
    /// The unit-test host is sandboxed and cannot write into the source tree, so the
    /// generator stages files in a fixed subdirectory of `NSTemporaryDirectory()`,
    /// prints that path (`GALLERY OUTPUT …`), and
    /// `scripts/generate-launch-gallery.swift` copies them into
    /// `Tests/Fixtures/Samples/` from outside the sandbox. An explicit
    /// `VITRINE_GALLERY_OUTPUT_DIR` override is honored for any non-sandboxed context.
    static var stagingDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["VITRINE_GALLERY_OUTPUT_DIR"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vitrine-gallery", isDirectory: true)
    }

    /// The on-disk URL of a sample's committed PNG within the fixtures directory.
    static func fixtureURL(for sample: SampleGallery.Sample) -> URL {
        fixturesDirectory.appendingPathComponent(sample.fileName)
    }
}

// MARK: - Manifest

/// The manifest written next to the committed gallery PNGs
/// (`Tests/Fixtures/Samples/manifest.json`), describing what was generated.
///
/// Unlike the golden manifest, this one is **not** pinned to a runner image: the
/// gallery is design-review evidence, not a byte-exact baseline, so the artifact
/// suite checks presence and catalog-sync (counts, ids, fingerprints, categories)
/// rather than pixel identity. Recording the generating OS still helps a reviewer
/// know which image produced the committed PNGs.
struct GalleryManifest: Codable, Equatable {
    /// Schema version so a future format change is detectable.
    var schema: Int
    /// The macOS version the committed PNGs were generated on (informational).
    var generatedOnOS: String
    /// Per-sample metadata, keyed by the sample's slug id.
    var samples: [String: SampleRecord]

    /// The current schema version, bumped only on a deliberate format change.
    static let currentSchema = 1
    /// The on-disk file name within the gallery directory.
    static let fileName = "manifest.json"

    /// What the manifest records for one sample.
    struct SampleRecord: Codable, Equatable {
        /// The sample's category raw value, so the manifest documents coverage.
        var category: String
        /// The gallery caption.
        var caption: String
        /// Rendered width in pixels.
        var width: Int
        /// Rendered height in pixels.
        var height: Int
        /// A content hash of the sample's deterministic config (see
        /// `SampleGallery.fingerprint`), so a stale fixture is detectable from the
        /// manifest alone.
        var configFingerprint: String
    }

    /// The default URL of the manifest under a gallery directory.
    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Loads and decodes a manifest from `directory`, or `nil` if absent/unparseable.
    static func load(from directory: URL) -> GalleryManifest? {
        guard let data = try? Data(contentsOf: url(in: directory)) else { return nil }
        return try? JSONDecoder().decode(GalleryManifest.self, from: data)
    }

    /// Encodes the manifest as pretty-printed, key-sorted JSON (deterministic so a
    /// re-generate produces a minimal diff).
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Render regression (always on)

/// Renders every gallery sample on any machine and asserts the pipeline produces a
/// real image, so a routine `make test` exercises the full launch-gallery set end to
/// end ("sample generation command" coverage, runnable without the opt-in).
@MainActor
@Suite("Sample gallery — render regression")
struct SampleGalleryTests {
    @Test func catalogIsNonEmpty() {
        #expect(!SampleGallery.all.isEmpty)
    }

    @Test func everyCategoryIsRepresented() {
        let present = Set(SampleGallery.all.map(\.category))
        for category in SampleGallery.Category.allCases {
            #expect(
                present.contains(category),
                "no launch-gallery sample covers \(category.rawValue)")
        }
    }

    @Test func sampleIDsAreUnique() {
        let ids = SampleGallery.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate sample id in the gallery catalog")
    }

    @Test func everySampleRenders() {
        for sample in SampleGallery.all {
            guard
                let image = ExportManager.renderCGImage(
                    sample.config, scale: sample.scale, fixedSize: sample.fixedSize)
            else {
                Issue.record("render failed for sample \(sample.id)")
                continue
            }
            #expect(image.width > 0 && image.height > 0, "empty render for \(sample.id)")
            #expect(
                ExportManager.pngData(from: image) != nil,
                "PNG encode failed for \(sample.id)")
        }
    }

    /// The fixed-size OpenGraph preset must render at exactly 1200×630 so its
    /// committed gallery fixture is the canonical link-card size.
    @Test func openGraphSampleIsExactSize() throws {
        let sample = try #require(
            SampleGallery.sample(withID: "preset-opengraph"),
            "the OpenGraph preset sample is missing from the catalog")
        let fixedSize = try #require(
            sample.fixedSize, "the OpenGraph sample should carry a fixed canvas size")
        let image = try #require(
            ExportManager.renderCGImage(sample.config, scale: sample.scale, fixedSize: fixedSize),
            "OpenGraph sample failed to render")
        #expect(image.width == Int(fixedSize.width * sample.scale))
        #expect(image.height == Int(fixedSize.height * sample.scale))
    }

    /// The accessibility sample's palette must clear the WCAG AA normal-text
    /// threshold for foreground-on-card and every token color, proving the
    /// "high-contrast state" is genuinely high contrast rather than a label.
    @Test func accessibilitySampleMeetsContrast() throws {
        let palette = SampleGallery.highContrastPalette
        let card = palette.background.color
        let pairs: [(String, Color)] = [
            ("foreground", palette.foreground.color),
            ("keyword", palette.keyword.color),
            ("string", palette.string.color),
            ("comment", palette.comment.color),
            ("number", palette.number.color),
            ("type", palette.type.color),
            ("function", palette.function.color),
            ("variable", palette.variable.color),
            ("attribute", palette.attribute.color),
        ]
        for (name, color) in pairs {
            let ratio = Brand.Contrast.ratio(color, on: card)
            #expect(
                ratio >= Brand.Contrast.aaNormal,
                "high-contrast \(name) only reaches \(String(format: "%.2f", ratio)):1, below WCAG AA"
            )
        }
    }

    /// The stale-fixture guard (`SampleArtifactTests.manifestMatchesCatalogWhenCommitted`)
    /// only works if `fingerprint(for:)` genuinely has the properties it claims: it
    /// must be a real digest, *deterministic* (same config → same hash, so a
    /// re-generate is a minimal diff and the manifest check is not flaky), and it must
    /// *discriminate* between distinct samples (so a changed input invalidates the
    /// recorded hash). The manifest-vs-catalog check cannot prove any of this on its
    /// own — it compares the fingerprint against itself, which a hard-coded constant
    /// would also satisfy. These assertions fail loudly for that degenerate
    /// implementation. This mirrors the golden suite's fingerprint guard.
    @Test func configFingerprintIsStableDistinctAndAFullDigest() {
        for sample in SampleGallery.all {
            #expect(
                SampleGallery.fingerprint(for: sample)
                    == SampleGallery.fingerprint(for: sample),
                "fingerprint for \(sample.id) is not stable across calls")
            // A SHA-256 hex digest is 64 characters; a truncated or empty value would
            // mean the descriptor was never actually hashed.
            #expect(
                SampleGallery.fingerprint(for: sample).count == 64,
                "fingerprint for \(sample.id) is not a full SHA-256 hex digest")
        }
        // All 27 catalog samples differ on at least one pixel-affecting axis, so their
        // fingerprints must all be distinct. A collision means the hash is ignoring a
        // field the committed PNG depends on.
        let fingerprints = SampleGallery.all.map(SampleGallery.fingerprint(for:))
        #expect(
            Set(fingerprints).count == SampleGallery.all.count,
            "two gallery samples share a fingerprint; the hash is missing a pixel-affecting field")
    }

    /// Proves the fingerprint actually reacts to each field the committed PNG depends
    /// on. `configFingerprintIsStableDistinctAndAFullDigest` shows the *current*
    /// catalog has no collisions, but not that a *future* edit to any one field would
    /// be noticed — a fingerprint that hashed only, say, the code string would pass
    /// that test yet silently keep a stale PNG when the theme or scale changed. Here we
    /// mutate one pixel-affecting field at a time on a copy of a sample and require the
    /// fingerprint to move, so the manifest's staleness detection is verified field by
    /// field.
    @Test func fingerprintIsSensitiveToEveryPixelAffectingField() {
        let base = SampleGallery.sample(withID: "theme-one-dark") ?? SampleGallery.all[0]
        let baseline = SampleGallery.fingerprint(for: base)

        /// Builds a sample identical to `base` except for one mutated config field and
        /// returns its fingerprint. The id is held constant so the change under test is
        /// only the mutated field, never the id (which the hash also folds in).
        func fingerprint(mutating mutate: (inout SnapshotConfig) -> Void) -> String {
            var config = base.config
            mutate(&config)
            let variant = SampleGallery.Sample(
                id: base.id, category: base.category, caption: base.caption,
                scale: base.scale, fixedSize: base.fixedSize, config: config)
            return SampleGallery.fingerprint(for: variant)
        }

        let mutations: [(field: String, mutate: (inout SnapshotConfig) -> Void)] = [
            ("code", { $0.code += "\n// changed" }),
            ("language", { $0.language = $0.language == .swift ? .python : .swift }),
            ("theme", { $0.theme = $0.theme.id == "dracula" ? .nord : .dracula }),
            ("fontName", { $0.fontName += "X" }),
            ("fontSize", { $0.fontSize += 1 }),
            ("fontLigatures", { $0.fontLigatures.toggle() }),
            ("padding", { $0.padding += 4 }),
            ("cornerRadius", { $0.cornerRadius += 2 }),
            ("showChrome", { $0.showChrome.toggle() }),
            ("showShadow", { $0.showShadow.toggle() }),
            ("showLineNumbers", { $0.showLineNumbers.toggle() }),
            ("highlightedLineRanges", { $0.highlightedLineRanges = [1...2] }),
            ("background", { $0.background = .transparent }),
        ]
        for mutation in mutations {
            #expect(
                fingerprint(mutating: mutation.mutate) != baseline,
                "fingerprint ignores the \(mutation.field) field; a change to it would not invalidate the committed PNG"
            )
        }

        // The render scale lives on the Sample, not the config; prove it too is folded
        // into the hash so a resolution change invalidates the fixture.
        let scaled = SampleGallery.Sample(
            id: base.id, category: base.category, caption: base.caption,
            scale: base.scale + 1, fixedSize: base.fixedSize, config: base.config)
        #expect(
            SampleGallery.fingerprint(for: scaled) != baseline,
            "fingerprint ignores the render scale; a resolution change would not invalidate the PNG"
        )
    }

    /// The generator writes `manifest.json` with `encoded()` and the artifact suite
    /// reads it back with `GalleryManifest.load` (`JSONDecoder`); if those two halves
    /// disagree, the catalog-sync check silently never runs against real data. Prove
    /// the contract directly: a manifest survives encode → decode unchanged, and the
    /// encoding is byte-stable (sorted keys) so a re-generate yields a minimal diff
    /// rather than reshuffled JSON. This mirrors the golden manifest round-trip.
    @Test func manifestRoundTripsAndEncodesDeterministically() throws {
        let original = GalleryManifest(
            schema: GalleryManifest.currentSchema,
            generatedOnOS: "26.0.0",
            samples: [
                "theme-nord": GalleryManifest.SampleRecord(
                    category: "theme", caption: "Nord theme",
                    width: 848, height: 556, configFingerprint: "nord-hash"),
                "lang-python": GalleryManifest.SampleRecord(
                    category: "language", caption: "Python on Dracula",
                    width: 600, height: 300, configFingerprint: "python-hash"),
            ])

        let encoded = try original.encoded()
        let decoded = try JSONDecoder().decode(GalleryManifest.self, from: encoded)
        #expect(decoded == original, "manifest did not survive an encode → decode round-trip")

        // Encoding the same value twice must produce identical bytes (the generator
        // relies on this so an unchanged gallery re-generates to a no-op diff).
        #expect(try original.encoded() == encoded, "manifest encoding is not deterministic")
    }
}

// MARK: - Artifact presence (always on, once committed)

/// Asserts the committed gallery fixtures exist and stay in sync with the catalog
/// ("artifact presence assertions"). These checks run on every machine; they
/// gate on whether the fixtures have been generated and committed yet, so the first
/// landing of the catalog (before `make gallery` has run) is not a hard failure —
/// once a manifest is present, every sample and the counts must match.
@MainActor
@Suite("Sample gallery — committed artifacts")
struct SampleArtifactTests {
    /// Whether the gallery has been generated and committed (a manifest is present).
    /// When it has not, the presence assertions become informational so the catalog
    /// can land before the fixtures are recorded on the pinned image.
    var isCommitted: Bool {
        FileManager.default.fileExists(
            atPath: GalleryManifest.url(in: SampleGalleryPaths.fixturesDirectory).path)
    }

    @Test func manifestMatchesCatalogWhenCommitted() throws {
        guard isCommitted else {
            print("GALLERY ARTIFACTS not yet committed — run `make gallery` to generate them.")
            return
        }
        let manifest = try #require(
            GalleryManifest.load(from: SampleGalleryPaths.fixturesDirectory),
            "gallery manifest.json present but unreadable")
        #expect(manifest.schema == GalleryManifest.currentSchema)
        #expect(
            manifest.samples.count == SampleGallery.all.count,
            """
            manifest lists \(manifest.samples.count) samples but the catalog has \
            \(SampleGallery.all.count) — regenerate with `make gallery`
            """)
        for sample in SampleGallery.all {
            let record = try #require(
                manifest.samples[sample.id],
                "no manifest entry for sample \(sample.id) — regenerate with `make gallery`")
            #expect(
                record.configFingerprint == SampleGallery.fingerprint(for: sample),
                "sample \(sample.id) changed since it was generated — regenerate with `make gallery`"
            )
            #expect(record.category == sample.category.rawValue)
        }
    }

    @Test func everySamplePNGExistsWhenCommitted() {
        guard isCommitted else { return }
        for sample in SampleGallery.all {
            let url = SampleGalleryPaths.fixtureURL(for: sample)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "missing committed gallery image \(sample.fileName) — regenerate with `make gallery`"
            )
        }
    }
}

// MARK: - Generator (opt-in)

/// Whether the gallery generator is armed: the opt-in `VITRINE_GENERATE_GALLERY`
/// flag must be present and truthy. Off by default so a routine test run never
/// rewrites a fixture.
///
/// A free helper (not a static on the suite) so the `@Suite(.enabled(if:))` trait —
/// a `Sendable`, nonisolated closure — can read it without the macro hitting a
/// circular reference to the type it is attached to (the same pattern as the golden
/// recorder).
enum GalleryGeneration {
    /// `nonisolated` so the `@Suite(.enabled(if:))` trait can read it from any
    /// context; it only touches `ProcessInfo`.
    nonisolated static var isActive: Bool {
        guard let value = ProcessInfo.processInfo.environment["VITRINE_GENERATE_GALLERY"] else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }
}

/// The launch-gallery **generator**.
///
/// `make gallery` runs only this suite with `VITRINE_GENERATE_GALLERY=1`. It renders
/// every catalog sample through the production export path and stages the PNGs plus
/// `manifest.json` in the sandboxed host's container temp, printing the staging path
/// on one `GALLERY OUTPUT <path>` line. `scripts/generate-launch-gallery.swift` then
/// copies the staged files into `Tests/Fixtures/Samples/` from outside the sandbox.
///
/// It is opt-in and deliberately isolated from the artifact checks so the suite can
/// never silently "fix" a missing artifact — regenerating the gallery is always an
/// explicit, reviewed step.
@MainActor
@Suite(
    "Sample gallery — generator",
    .enabled(
        if: GalleryGeneration.isActive,
        "set VITRINE_GENERATE_GALLERY=1 (make gallery) to (re)generate the launch gallery"))
struct SampleGalleryGeneratorTests {
    /// Renders every sample, writes its PNG, and writes the manifest. One test keeps
    /// the write coherent: the PNGs and the manifest are produced together from the
    /// same render pass.
    @Test func generateGallery() throws {
        let directory = SampleGalleryPaths.stagingDirectory
        // Start clean so a stale file from a previous run can never be copied in.
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The single machine-readable line the script parses to find the staged files.
        print("GALLERY OUTPUT \(directory.path)")

        var records: [String: GalleryManifest.SampleRecord] = [:]
        for sample in SampleGallery.all {
            let image = try #require(
                ExportManager.renderCGImage(
                    sample.config, scale: sample.scale, fixedSize: sample.fixedSize),
                "gallery render failed for \(sample.id)")
            let png = try #require(
                ExportManager.pngData(from: image), "PNG encode failed for \(sample.id)")
            let url = directory.appendingPathComponent(sample.fileName)
            try png.write(to: url)
            records[sample.id] = GalleryManifest.SampleRecord(
                category: sample.category.rawValue,
                caption: sample.caption,
                width: image.width,
                height: image.height,
                configFingerprint: SampleGallery.fingerprint(for: sample))
            print("GALLERY SAMPLE \(sample.id) \(image.width)x\(image.height) \(url.path)")
        }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let manifest = GalleryManifest(
            schema: GalleryManifest.currentSchema,
            generatedOnOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            samples: records)
        try manifest.encoded().write(to: GalleryManifest.url(in: directory))
        print("GALLERY MANIFEST \(records.count) samples")
    }
}
