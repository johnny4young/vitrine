import AppKit
import SwiftUI
import Testing
import VitrineRendering

@testable import Vitrine

@Suite("App chrome contrast")
struct ChromeContrastTests {
    @Test(arguments: [
        NSAppearance.Name.aqua, .darkAqua,
    ])
    func brightSystemAccentsReadAsTextOnASettingsGroup(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let group = VitrineTokens.Accent.composite(
                NSColor(VitrineTokens.Chrome.tile), over: NSColor(VitrineTokens.Surface.window))
            for accent: NSColor in [
                .systemGreen, .systemYellow, .systemOrange, .systemPink, .systemTeal, .systemGray,
                .systemIndigo, .systemPurple, .systemBlue, .systemRed,
            ] {
                let text = VitrineTokens.Accent.legibleText(accent: accent, on: group)
                let ratio = Brand.Contrast.ratio(Color(nsColor: text), on: Color(nsColor: group))
                #expect(
                    ratio >= Brand.Contrast.aaNormal, "\(accent): \(ratio):1 in \(name.rawValue)")
            }
        }
    }

    @Test(arguments: [
        NSAppearance.Name.aqua, .darkAqua,
    ])
    func whiteProminentLabelReadsOnTheFill(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let ratio = Brand.Contrast.ratio(.white, on: VitrineTokens.Accent.systemProminentFill)
            #expect(ratio >= Brand.Contrast.aaNormal, "\(ratio):1 in \(name.rawValue)")
        }
    }

    @Test(arguments: [
        NSAppearance.Name.aqua, .darkAqua,
    ])
    func accentAndDestructiveTintsReadOnASettingsGroup(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let group = VitrineTokens.Accent.composite(
                NSColor(VitrineTokens.Chrome.tile), over: NSColor(VitrineTokens.Surface.window))
            for tint in [VitrineTokens.Accent.systemText, VitrineTokens.Accent.destructiveText] {
                let ratio = Brand.Contrast.ratio(tint, on: Color(nsColor: group))
                #expect(ratio >= Brand.Contrast.aaNormal, "\(ratio):1 in \(name.rawValue)")
            }
        }
    }

    @Test func anAccentThatAlreadyReadsStaysUnchanged() {
        let accent = NSColor(srgbRed: 0.1, green: 0.1, blue: 0.5, alpha: 1)
        let text = VitrineTokens.Accent.legibleText(accent: accent, on: .white)
        #expect(text == accent)
    }

    @Test(arguments: [
        NSAppearance.Name.aqua, .darkAqua,
    ])
    func normalSizeChromeLabelsMeetAA(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let texts = [
                ("primary", VitrineTokens.Text.primary),
                ("secondary", VitrineTokens.Text.secondary),
                ("tertiary", VitrineTokens.Text.tertiary),
            ]
            let surfaces = [
                ("window", VitrineTokens.Surface.window),
                ("card", VitrineTokens.Surface.card),
                ("inset", VitrineTokens.Surface.inset),
                ("row", VitrineTokens.Surface.row),
                ("status", VitrineTokens.Chrome.statusCapsule),
            ]
            for (_, background) in surfaces {
                #expect(NSColor(background).alphaComponent == 1)
            }
            for (tier, text) in texts {
                for (surface, background) in surfaces {
                    let ratio = Brand.Contrast.ratio(text, on: background)
                    #expect(
                        ratio >= Brand.Contrast.aaNormal,
                        "\(tier) on \(surface) is \(ratio):1 in \(name.rawValue)")
                }
            }
        }
    }
    /// Constructing an increased-contrast NSAppearance is normalized by AppKit
    /// unless the real system setting is enabled. Test declared variants directly;
    /// the native Increase Contrast journey remains a separate acceptance gate.
    @Test(arguments: [ColorScheme.light, .dark])
    func declaredHighContrastLabelsMeetAA(_ scheme: ColorScheme) throws {
        let appearance = try #require(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance {
            for palette in [
                Brand.Palette.textPrimary, Brand.Palette.textSecondary,
                VitrineTokens.Text.tertiaryPalette,
            ] {
                for surface in [
                    VitrineTokens.Surface.window, VitrineTokens.Surface.card,
                    VitrineTokens.Surface.inset, VitrineTokens.Surface.row,
                ] {
                    let normal = Brand.Contrast.ratio(
                        palette.resolved(scheme: scheme, highContrast: false), on: surface)
                    let high = Brand.Contrast.ratio(
                        palette.resolved(scheme: scheme, highContrast: true), on: surface)
                    #expect(high >= 4.5)
                    #expect(high >= normal)
                }
            }
        }
    }

    /// The CTA stops are fixed, so one rendering covers both appearances.
    @Test(arguments: [false, true])
    func whiteCTALabelMeetsAAAcrossRenderedGradient(hovered: Bool) throws {
        let hoverBrightness = hovered ? VitrineTokens.Chrome.ctaHoverBrightness : 0
        let renderer = ImageRenderer(
            content:
                Rectangle().fill(VitrineTokens.Gradients.callToAction)
                .frame(width: 200, height: 40)
                .brightness(hoverBrightness))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixels = NSBitmapImageRep(cgImage: image)
        var minimum = Double.infinity
        for index in 0...10 {
            let color = try #require(pixels.colorAt(x: index * 199 / 10, y: index * 39 / 10))
            minimum = min(minimum, Brand.Contrast.ratio(.white, on: Color(nsColor: color)))
        }
        #expect(
            minimum >= 4.5,
            "White CTA text reaches only \(minimum):1 at brightness \(hoverBrightness)")
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func selectedAccentLabelMeetsAAWithTheCurrentSystemChoice(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let ratio = Brand.Contrast.ratio(
                VitrineTokens.Accent.systemContrast, on: VitrineTokens.Accent.system)
            #expect(ratio >= 4.5, "Selected accent label is only \(ratio):1 in \(name.rawValue)")
        }
    }

    /// SwiftUI's display-link renderer resolves dynamic colors off the main thread.
    @Test func accentColorsResolveOffTheMainThread() async {
        for color in [
            VitrineTokens.Accent.systemContrast, VitrineTokens.Accent.systemText,
            VitrineTokens.Accent.systemProminentFill,
        ] {
            let label = NSColor(color)
            let resolved = await Task.detached {
                (offMain: pthread_main_np() == 0, color: label.usingColorSpace(.sRGB))
            }.value
            #expect(resolved.offMain)
            #expect(resolved.color != nil)
        }
    }

    @Test
    func selectedLabelMeetsAAAcrossOpaqueRGBFills() {
        for red in stride(from: 0.0, through: 1.0, by: 0.1) {
            for green in stride(from: 0.0, through: 1.0, by: 0.1) {
                for blue in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let fill = Color(.sRGB, red: red, green: green, blue: blue)
                    let label = VitrineTokens.Text.readable(on: fill)
                    #expect(Brand.Contrast.ratio(label, on: fill) >= 4.5)
                }
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark], [false, true])
    func selectedBrandLabelMeetsAAWithoutChangingTheFill(
        scheme: ColorScheme, highContrast: Bool
    ) {
        let fill = Brand.Palette.accent.resolved(scheme: scheme, highContrast: highContrast)
        let label = VitrineTokens.Text.readable(on: fill)
        #expect(Brand.Contrast.ratio(label, on: fill) >= 4.5)
    }

}

@MainActor
@Suite("Paywall composition")
struct PaywallCompositionTests {
    /// Evaluates the body that holds the buy control, which adopts the accent fill.
    @Test func paywallComposesAtItsFixedWidth() {
        let host = NSHostingView(
            rootView: PaywallSheet(
                feature: .brandKit, entitlements: Entitlements(provider: FreeProvider())))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width == 380)
        #expect(host.fittingSize.height > 0)
    }
}
