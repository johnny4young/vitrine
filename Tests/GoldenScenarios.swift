import CoreGraphics
import CryptoKit
import Foundation
import SwiftUI

@testable import Vitrine

/// The shared catalog of golden-image scenarios.
///
/// This is the **single source of truth** consumed by both the recorder
/// (`GoldenRecorderTests`, which writes the committed PNG fixtures) and the
/// comparison suite (`GoldenImageTests`, which renders each scenario again and
/// pixel-diffs it against its fixture). Keeping one catalog guarantees the bytes
/// that were recorded and the bytes that are compared come from the *exact* same
/// `SnapshotConfig` and render parameters — a scenario can never drift between the
/// two without changing this file.
///
/// ## What the scenarios cover
///
/// The set spans the visual surfaces a screenshot
/// app must not silently regress: the **default** (signature) theme, a **light**
/// theme, a **transparent** background (real alpha), the **line-number** gutter, a
/// **selected-line highlight**, and the fixed-size **OpenGraph** preset. Each is a
/// deliberately small, deterministic snippet so the fixtures stay tiny and the
/// render is byte-stable on a given OS/Xcode image.
///
/// ## Determinism
///
/// Every field that affects pixels is pinned: the code text, the language, the
/// theme, the bundled `JetBrains Mono` font and its size, padding, chrome, and the
/// background. Colors resolve through fixed sRGB, and the render runs through the
/// same `ExportManager.renderCGImage` path the app's quick-capture and export use.
/// What is *not* invariant across machines is text rasterization (anti-aliasing
/// differs by OS version), which is precisely why the strict pixel comparison is
/// gated on the pinned runner image recorded in `manifest.json`.
enum GoldenScenario: String, CaseIterable, Sendable {
    /// The signature out-of-the-box look: One Dark on the Aurora gradient.
    case defaultTheme = "default-theme"
    /// A light syntax theme (One Light), to catch regressions specific to the
    /// light-appearance render path (gutter/badge tints flip on luminance).
    case lightTheme = "light-theme"
    /// A transparent canvas background, the load-bearing alpha case: the
    /// corners must stay fully clear with no opaque matte.
    case transparentBackground = "transparent-background"
    /// The line-number gutter enabled, which switches the code body from a single
    /// `Text` to the row-by-row layout.
    case lineNumbers = "line-numbers"
    /// A selected-line highlight band, the other half of the row-based layout —
    /// the translucent wash drawn behind chosen rows.
    case selectedLineHighlight = "selected-line-highlight"
    /// The fixed-size OpenGraph 1200×630 preset at 1×, the canonical link-preview
    /// card whose pixel dimensions are guaranteed regardless of content.
    case openGraph = "opengraph"

    /// The fixture file name for this scenario (a PNG under `Tests/Fixtures/Golden/`).
    var fileName: String { "\(rawValue).png" }

    /// A short human label for log lines (`GOLDEN …`).
    var label: String { rawValue }

    /// The render scale (resolution multiplier) for this scenario. Content
    /// scenarios use the app's default export scale (2×, the look users actually
    /// get); the OpenGraph preset pins 1× so its logical and pixel sizes match
    /// (1200×630), exactly as `ExportPreset.openGraph` declares.
    var scale: CGFloat {
        switch self {
        case .openGraph: 1
        default: 2
        }
    }

    /// The fixed logical canvas size for this scenario, or `nil` when the canvas
    /// hugs its content. Only the OpenGraph preset pins a size.
    var fixedSize: CGSize? {
        switch self {
        case .openGraph: ExportPreset.openGraph.sizing.fixedSize
        default: nil
        }
    }

    /// The exact rendered pixel size for a fixed-size scenario (`fixedSize × scale`),
    /// or `nil` for a content-hugging scenario. This dimension is **OS-independent**
    /// `ImageRenderer` produces exactly this size for a pinned `proposedSize` — so
    /// it can be asserted on any runner, unlike a hugging scenario whose size
    /// derives from text layout.
    var expectedFixedPixelSize: (width: Int, height: Int)? {
        guard let size = fixedSize else { return nil }
        return (Int(size.width * scale), Int(size.height * scale))
    }

    /// The exact `SnapshotConfig` rendered for this scenario. Deterministic: every
    /// pixel-affecting field is set explicitly so the recorder and the comparison
    /// suite render identical input.
    var config: SnapshotConfig {
        var config = SnapshotConfig()
        // Pin the typography for every scenario so a default-font change can never
        // silently reflow a golden (JetBrains Mono ships in the app bundle).
        config.fontName = CodeFont.default
        config.fontSize = 14
        config.fontLigatures = false
        // A short, idiomatic Swift snippet — small enough to keep fixtures tiny,
        // varied enough to exercise keyword/type/string/number/comment colors.
        config.code = Self.sampleCode
        config.language = .swift

        switch self {
        case .defaultTheme:
            // The untouched signature configuration; assert nothing else changes.
            break

        case .lightTheme:
            config.theme = .oneLight

        case .transparentBackground:
            config.background = .transparent

        case .lineNumbers:
            config.showLineNumbers = true

        case .selectedLineHighlight:
            // Highlight a couple of interior lines so the band is clearly visible
            // and distinct from the gutter case.
            config.highlightedLineRanges = [2...3]

        case .openGraph:
            // Apply the real OpenGraph preset's presentation guidance (padding +
            // background), exactly as the app does when the user picks it.
            ExportPreset.openGraph.apply(to: &config)
        }
        return config
    }

    /// Renders this scenario to a `CGImage` through the production export path
    /// (`ExportManager.renderCGImage`), normalized to sRGB. Returns `nil` only if
    /// the renderer itself fails — the callers treat that as a hard error.
    @MainActor
    func render() -> CGImage? {
        ExportManager.renderCGImage(config, scale: scale, fixedSize: fixedSize)
    }

    /// Renders this scenario and PNG-encodes it, the exact byte sequence the
    /// recorder writes and the comparison suite re-derives. Returns `nil` if the
    /// render or the PNG encode fails.
    @MainActor
    func renderedPNG() -> Data? {
        guard let image = render() else { return nil }
        return ExportManager.pngData(from: image)
    }

    /// A stable, content-derived fingerprint of this scenario's deterministic
    /// config and render parameters, recorded in the manifest.
    ///
    /// It is a SHA-256 over the pixel-affecting fields (code, language, theme,
    /// font, padding, chrome/shadow/line-number flags, highlight ranges, the
    /// background's non-PII kind, and the scale/fixed-size). A change to any input
    /// that would invalidate a committed PNG therefore changes the fingerprint, so
    /// the suite can detect a stale fixture from the manifest alone — before, and
    /// independently of, comparing a single pixel.
    var configFingerprint: String {
        let c = config
        let highlight = LineHighlight.normalize(c.highlightedLineRanges)
            .map { "\($0.lowerBound)-\($0.upperBound)" }
            .joined(separator: ",")
        let size = fixedSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "hug"
        let descriptor = [
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
            "scale=\(Int(scale))",
            "size=\(size)",
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(descriptor.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A small, deterministic Swift snippet shared by every scenario. Chosen to
    /// exercise a spread of token kinds (keyword, type, string, number, comment)
    /// without growing the committed PNGs.
    static let sampleCode = """
        // Vitrine golden fixture
        struct Badge: View {
            let count = 3
            var body: some View {
                Text("Items: \\(count)")
            }
        }
        """
}
