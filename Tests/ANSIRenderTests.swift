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

    @Test func normalizeCleansPseudoTerminalControlBytes() {
        #expect(ANSIRenderer.normalize("a\r\nb") == "a\nb")  // CRLF → LF
        #expect(ANSIRenderer.normalize("a\rb") == "b")  // lone CR redraws the line
        #expect(ANSIRenderer.normalize("10%\r20%\rDone\n") == "Done\n")
        #expect(ANSIRenderer.normalize("abc\u{08}d") == "abd")  // backspace redraw
        #expect(ANSIRenderer.normalize("x\u{04}y\u{07}z") == "xyz")  // ^D / BEL dropped
        // Tab, newline, and ESC (the parser consumes ESC) are preserved.
        #expect(ANSIRenderer.normalize("a\tb\n\(esc)[0m") == "a\tb\n\(esc)[0m")
        #expect(ANSIRenderer.normalize("plain text") == "plain text")
    }

    @Test func shellInitEmitsTheHelpers() {
        let zsh = ShellInit.snippet(for: .zsh)
        #expect(zsh.contains("vgrab()") && zsh.contains("vlast()"))
        #expect(zsh.contains("script -q") && zsh.contains("--copy"))
        #expect(ShellInit.snippet(for: .bash).contains("vgrab()"))
        #expect(ShellInit.resolveShell("zsh") == .zsh)
        #expect(ShellInit.resolveShell("bash") == .bash)
        #expect(ShellInit.resolveShell("fish") == nil)
    }

    @Test func shellInitArgumentParsing() {
        #expect(ShellInit.invocation(for: ["zsh"]) == .snippet(.zsh))
        #expect(ShellInit.invocation(for: ["bash"]) == .snippet(.bash))
        #expect(ShellInit.invocation(for: ["--help"]) == .help)
        #expect(ShellInit.invocation(for: ["-h"]) == .help)
        // --help wins in any position, not just the first.
        #expect(ShellInit.invocation(for: ["zsh", "--help"]) == .help)
        // Extra positional arguments are surfaced, not silently ignored.
        #expect(ShellInit.invocation(for: ["zsh", "extra"]) == .extraArguments(["extra"]))
        // An unknown single argument is reported as an unknown shell.
        #expect(ShellInit.invocation(for: ["fish"]) == .unknownShell("fish"))
    }

    @Test func terminalPaletteFollowsTheTheme() {
        // Light theme → light terminal; dark theme → the default dark palette;
        // a signature theme (Dracula) → its own palette.
        #expect(
            ANSIPalette.forTheme(.github).defaultBackground
                == ANSIPalette.terminalLight.defaultBackground)
        #expect(
            ANSIPalette.forTheme(.oneDark).defaultBackground
                == ANSIPalette.terminal.defaultBackground)
        #expect(
            ANSIPalette.forTheme(.dracula).defaultBackground
                == ANSIPalette.dracula.defaultBackground)
    }

    @Test func terminalRenderDiffersBetweenLightAndDarkThemes() throws {
        var dark = SnapshotConfig()
        dark.language = .terminal
        dark.code = "\(esc)[31mmodified:\(esc)[0m file.swift"
        dark.theme = .oneDark
        var light = dark
        light.theme = .github

        let darkImage = try #require(ExportManager.renderCGImage(dark, scale: 1))
        let lightImage = try #require(ExportManager.renderCGImage(light, scale: 1))
        let darkPNG = try #require(ExportManager.pngData(from: darkImage))
        let lightPNG = try #require(ExportManager.pngData(from: lightImage))
        #expect(darkPNG != lightPNG, "terminal render should follow the theme's light/dark palette")
    }

    private func approx(_ color: NSColor, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return false }
        return abs(c.redComponent - r) < 0.01 && abs(c.greenComponent - g) < 0.01
            && abs(c.blueComponent - b) < 0.01
    }
}
