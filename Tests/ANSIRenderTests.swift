import AppKit
import Testing

@testable import Vitrine

/// The ANSI palette (index → color) and the attributed-string builder, plus the
/// detector wiring that routes pasted terminal output to the terminal renderer.
@Suite("ANSI render + detection")
@MainActor
struct ANSIRenderTests {
    private let esc = "\u{1B}"
    private let palette = ANSIPalette.terminal

    @Test func indexedColorFollowsTheXterm256Layout() {
        // 0–15 are the base palette.
        #expect(palette.indexedColor(0) == palette.base[0])
        #expect(palette.indexedColor(15) == palette.base[15])
        // 16 is the cube origin (black); 231 is the cube max (white).
        #expect(approx(palette.indexedColor(16), 0, 0, 0))
        #expect(approx(palette.indexedColor(231), 1, 1, 1))
        // 232–255 is the grayscale ramp (a single channel, equal across RGB).
        let gray = palette.indexedColor(240).usingColorSpace(.sRGB)!
        #expect(abs(gray.redComponent - gray.greenComponent) < 0.001)
        #expect(abs(gray.greenComponent - gray.blueComponent) < 0.001)
        // Out-of-range indices clamp rather than crash.
        #expect(palette.indexedColor(999) == palette.indexedColor(255))
    }

    @Test func truecolorResolvesDirectly() {
        let resolved = palette.color(.rgb(10, 20, 30), fallback: .black).usingColorSpace(.sRGB)!
        #expect(abs(resolved.redComponent - 10.0 / 255) < 0.001)
        #expect(abs(resolved.greenComponent - 20.0 / 255) < 0.001)
        #expect(abs(resolved.blueComponent - 30.0 / 255) < 0.001)
    }

    @Test func attributedStringAppliesForegroundPerRun() {
        let attributed = ANSIRenderer.attributedString(
            "\(esc)[31mred\(esc)[0m plain",
            font: .monospacedSystemFont(ofSize: 13, weight: .regular))
        #expect(attributed.string == "red plain")
        let redColor =
            attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(redColor == palette.indexedColor(1))
        // The trailing " plain" run resolves to the default foreground.
        let plainColor =
            attributed.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor
        #expect(plainColor == palette.defaultForeground)
    }

    @Test func defaultBackgroundIsTransparentButExplicitIsPainted() {
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        // A plain run paints no background (the canvas terminal fill shows through).
        let plain = ANSIRenderer.attributedString("hi", font: font)
        #expect(plain.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        // An explicit `41m` (red bg) run paints one.
        let painted = ANSIRenderer.attributedString("\(esc)[41mx", font: font)
        #expect(
            painted.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor
                == palette.indexedColor(1))
    }

    @Test func detectorRoutesANSIToTerminal() {
        #expect(LanguageDetector.detect("\(esc)[32m$ ls\(esc)[0m\nfile.txt") == .terminal)
        #expect(LanguageDetector.interpret("\(esc)[31merror\(esc)[0m").language == .terminal)
        // Plain source is unaffected.
        #expect(LanguageDetector.detect("func greet() {}") != .terminal)
    }

    private func approx(_ color: NSColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        return abs(c.redComponent - r) < 0.01 && abs(c.greenComponent - g) < 0.01
            && abs(c.blueComponent - b) < 0.01
    }
}
