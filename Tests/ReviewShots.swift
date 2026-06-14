import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Vitrine

/// Whether the review-shot generator is armed. Opt-in via `VITRINE_REVIEW_SHOTS=1`
/// so a routine test run never renders these. Mirrors `GalleryGeneration` (CS-039).
enum ReviewShotGeneration {
    nonisolated static var isActive: Bool {
        guard let value = ProcessInfo.processInfo.environment["VITRINE_REVIEW_SHOTS"] else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
    }
}

/// A one-off generator that renders one PNG per shipped feature (Phases 1–5) through
/// the production export path, for a human visual review. Opt-in and isolated from
/// the real suites; it asserts nothing, it just stages images and prints their path
/// on a `REVIEW OUTPUT <path>` line that the caller copies out of the sandbox.
@MainActor
@Suite(
    "Review shots — generator",
    .enabled(
        if: ReviewShotGeneration.isActive,
        "set VITRINE_REVIEW_SHOTS=1 to render the feature review screenshots"))
struct ReviewShotsGeneratorTests {
    /// A demo snippet with a "secret" line (for the blur showcase) and enough lines
    /// to exercise highlighting, focus, and arrows.
    private static let sampleCode = """
        struct Counter {
            private(set) var value = 0

            mutating func increment(by step: Int = 1) {
                value += step
            }
        }

        let apiKey = "sk-live-3f9a2c8b1d7e6055"
        var counter = Counter()
        counter.increment(by: 3)
        print("Total: \\(counter.value)")
        """

    /// A small unified-diff snippet for the diff-bands showcase.
    private static let diffCode = """
        struct Counter {
        -    var value = 0
        +    private(set) var value = 0

        -    func increment() {
        -        value += 1
        +    mutating func increment(by step: Int = 1) {
        +        value += step
            }
        }
        """

    private func base() -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = Self.sampleCode
        config.language = .swift
        config.theme = .oneDark
        config.background = .gradient(.aurora)
        config.showChrome = true
        config.showShadow = true
        return config
    }

    private func red() -> RGBAColor { Annotation.defaultColor }

    @Test func generateReviewShots() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vitrine-review", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("REVIEW OUTPUT \(directory.path)")

        // Each entry: (file id, config, fixedSize, scale).
        var shots: [(String, SnapshotConfig, CGSize?, CGFloat)] = []

        // P1 — window title + corner radius + shadow.
        shots.append(("01-baseline", base(), nil, 2))
        var titled = base()
        titled.windowTitle = "Counter.swift"
        shots.append(("02-window-title", titled, nil, 2))
        var rounded = base()
        rounded.cornerRadius = 24
        rounded.shadowRadius = 36
        rounded.windowTitle = "Counter.swift"
        shots.append(("03-rounded-shadow", rounded, nil, 2))

        // Line numbers + highlight.
        var numbered = base()
        numbered.showLineNumbers = true
        shots.append(("04-line-numbers", numbered, nil, 2))

        // P2 — focus mode (dim non-highlighted lines).
        var focus = base()
        focus.showLineNumbers = true
        focus.highlightedLineRanges = [4...6]
        focus.focusHighlightedLines = true
        shots.append(("05-focus-mode", focus, nil, 2))

        // P3 — diff bands.
        var diff = base()
        diff.code = Self.diffCode
        diff.language = .diff
        diff.showLineNumbers = true
        diff.diffDecorations = true
        diff.windowTitle = "Counter.swift.diff"
        shots.append(("06-diff-bands", diff, nil, 2))

        // P4 — social presets (new export shapes).
        if let story = ExportPreset.preset(withID: "instagram-story") {
            var config = base()
            story.apply(to: &config)
            shots.append(
                ("07-preset-instagram-story", config, story.sizing.fixedSize, CGFloat(story.scale)))
        }
        if let banner = ExportPreset.preset(withID: "github-banner") {
            var config = base()
            banner.apply(to: &config)
            shots.append(
                ("08-preset-github-banner", config, banner.sizing.fixedSize, CGFloat(banner.scale)))
        }

        // P5 — annotations.
        var arrow = base()
        arrow.windowTitle = "Counter.swift"
        arrow.annotations = [
            Annotation(
                kind: .arrow, start: CGPoint(x: 0.60, y: 0.86), end: CGPoint(x: 0.28, y: 0.66))
        ]
        shots.append(("09-annotation-arrow", arrow, nil, 2))

        var text = base()
        text.windowTitle = "Counter.swift"
        text.annotations = [
            Annotation(
                kind: .text, start: CGPoint(x: 0.62, y: 0.30), end: CGPoint(x: 0.62, y: 0.30),
                text: "Refactor this")
        ]
        shots.append(("10-annotation-text", text, nil, 2))

        var blur = base()
        blur.windowTitle = "Counter.swift"
        blur.annotations = [
            Annotation(
                kind: .blur, start: CGPoint(x: 0.10, y: 0.60), end: CGPoint(x: 0.72, y: 0.68))
        ]
        shots.append(("11-annotation-blur", blur, nil, 2))

        // P6 — new annotation kinds (CleanShot-style toolbar).
        func rgba(_ hex: String) -> RGBAColor { RGBAColor(Color(hex: hex)) }

        var counter = base()
        counter.windowTitle = "Counter.swift"
        counter.annotations = [
            Annotation(
                kind: .counter, start: CGPoint(x: 0.07, y: 0.20), end: .zero, thickness: 6,
                number: 1),
            Annotation(
                kind: .counter, start: CGPoint(x: 0.07, y: 0.34), end: .zero, thickness: 6,
                number: 2),
            Annotation(
                kind: .counter, start: CGPoint(x: 0.07, y: 0.66), end: .zero, thickness: 6,
                number: 3),
        ]
        shots.append(("12-annotation-counter", counter, nil, 2))

        var highlighter = base()
        highlighter.windowTitle = "Counter.swift"
        highlighter.annotations = [
            // A marker swipe over real text (line 2 and the apiKey line), the way
            // CleanShot's highlighter reads — content stays legible through it.
            Annotation(
                kind: .highlighter, start: CGPoint(x: 0.12, y: 0.175),
                end: CGPoint(x: 0.53, y: 0.245),
                color: rgba("#FF375F")),
            Annotation(
                kind: .highlighter, start: CGPoint(x: 0.10, y: 0.61),
                end: CGPoint(x: 0.78, y: 0.69),
                color: rgba("#FFD60A")),
        ]
        shots.append(("13-annotation-highlighter", highlighter, nil, 2))

        var rectangle = base()
        rectangle.windowTitle = "Counter.swift"
        rectangle.annotations = [
            Annotation(
                kind: .rectangle, start: CGPoint(x: 0.05, y: 0.16), end: CGPoint(x: 0.74, y: 0.52),
                color: rgba("#0A84FF"), thickness: 5)
        ]
        shots.append(("14-annotation-rectangle", rectangle, nil, 2))

        var line = base()
        line.windowTitle = "Counter.swift"
        line.annotations = [
            Annotation(
                kind: .line, start: CGPoint(x: 0.10, y: 0.40), end: CGPoint(x: 0.62, y: 0.40),
                color: rgba("#FF9F0A"), thickness: 4)
        ]
        shots.append(("15-annotation-line", line, nil, 2))

        // The hero: a multi-tool markup the way a finished CleanShot annotation looks.
        var hero = base()
        hero.windowTitle = "Counter.swift"
        hero.annotations = [
            Annotation(
                kind: .rectangle, start: CGPoint(x: 0.05, y: 0.16), end: CGPoint(x: 0.74, y: 0.52),
                color: rgba("#0A84FF"), thickness: 5),
            Annotation(
                kind: .counter, start: CGPoint(x: 0.07, y: 0.20), end: .zero, thickness: 6,
                number: 1),
            Annotation(
                kind: .blur, start: CGPoint(x: 0.10, y: 0.60), end: CGPoint(x: 0.72, y: 0.68)),
            Annotation(
                kind: .arrow, start: CGPoint(x: 0.80, y: 0.84), end: CGPoint(x: 0.55, y: 0.66),
                thickness: 6),
            Annotation(
                kind: .text, start: CGPoint(x: 0.74, y: 0.91), end: .zero, text: "Redacted",
                color: red()),
        ]
        shots.append(("16-annotations-hero", hero, nil, 2))

        for (id, config, fixedSize, scale) in shots {
            let image = try #require(
                ExportManager.renderCGImage(config, scale: scale, fixedSize: fixedSize),
                "render failed for \(id)")
            let png = try #require(
                ExportManager.pngData(from: image), "PNG encode failed for \(id)")
            let url = directory.appendingPathComponent("\(id).png")
            try png.write(to: url)
            print("REVIEW SHOT \(id) \(image.width)x\(image.height)")
        }
        print("REVIEW DONE \(shots.count) shots")
    }
}
