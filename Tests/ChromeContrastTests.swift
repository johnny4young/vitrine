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

    /// The tool row: the stage at 0.6 over the window, under the hover tint. Variants are
    /// resolved directly because AppKit normalizes a constructed increased-contrast appearance.
    @Test(arguments: [ColorScheme.light, .dark], [false, true])
    func hoveredToolInkMeetsAAOnTheTint(scheme: ColorScheme, highContrast: Bool) throws {
        let appearance = try #require(NSAppearance(named: scheme == .dark ? .darkAqua : .aqua))
        appearance.performAsCurrentDrawingAppearance {
            let row = VitrineTokens.Accent.composite(
                NSColor(
                    Brand.Palette.stage.resolved(scheme: scheme, highContrast: highContrast)
                        .opacity(0.6)),
                over: NSColor(VitrineTokens.Surface.window))
            let tinted = VitrineTokens.Accent.composite(
                NSColor(
                    VitrineTokens.Chrome.toolHoverFillPalette.resolved(
                        scheme: scheme, highContrast: highContrast)),
                over: row)
            for ink in [Brand.Palette.textPrimary, Brand.Palette.textSecondary] {
                let ratio = Brand.Contrast.ratio(
                    ink.resolved(scheme: scheme, highContrast: highContrast),
                    on: Color(nsColor: tinted))
                #expect(ratio >= Brand.Contrast.aaNormal, "\(ratio):1 on \(tinted)")
            }
        }
    }

    /// 3:1 is WCAG's floor for non-text indicators, which `aaLarge` shares.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func selectedSwatchRingReadsOnEverySurfaceItSitsOn(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let group = VitrineTokens.Accent.composite(
                NSColor(VitrineTokens.Chrome.tile), over: NSColor(VitrineTokens.Surface.window))
            let surfaces = [
                VitrineTokens.Surface.window, VitrineTokens.Surface.card,
                VitrineTokens.Surface.inset, Color(nsColor: group),
            ]
            for surface in surfaces {
                let ratio = Brand.Contrast.ratio(
                    VitrineTokens.Chrome.swatchSelectedBorder, on: surface)
                #expect(ratio >= Brand.Contrast.aaLarge, "\(ratio):1 in \(name.rawValue)")
            }
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func theCheckerCellsDiffer(_ name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        appearance.performAsCurrentDrawingAppearance {
            let ratio = Brand.Contrast.ratio(
                VitrineTokens.Chrome.checkerBase, on: VitrineTokens.Chrome.checkerSquare)
            #expect(ratio > 1.1, "\(ratio):1 in \(name.rawValue)")
        }
    }

    /// The palette holds white and near-black. Each must keep an edge on matching chrome,
    /// and an edge the user asked to strengthen meets the 3:1 non-text floor.
    @Test(arguments: [ColorScheme.light, .dark], [false, true])
    func annotationColorDotsKeepAnEdge(scheme: ColorScheme, highContrast: Bool) {
        let dot = scheme == .light ? Color.white : Color(hex: "#1C1C1E")
        for edge in [
            VitrineTokens.Chrome.colorDotEdgePalette, VitrineTokens.Chrome.paletteDotEdgePalette,
        ] {
            let drawn = VitrineTokens.Accent.composite(
                NSColor(edge.resolved(scheme: scheme, highContrast: highContrast)),
                over: NSColor(dot))
            let ratio = Brand.Contrast.ratio(Color(nsColor: drawn), on: dot)
            #expect(ratio >= (highContrast ? Brand.Contrast.aaLarge : 1.5), "\(ratio):1")
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
