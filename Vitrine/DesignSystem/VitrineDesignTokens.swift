import AppKit
import SwiftUI

/// The flat token namespace for the current designed app chrome.
///
/// `VitrineTokens` centralizes the design-system values and re-exports the existing
/// `Brand` palette where the two overlap, so current and older surfaces
/// resolve identical values from one source of truth. Every color is adaptive:
/// it carries the light and dark palette and resolves at draw time, so views
/// never branch on the appearance themselves — and never hard-code a hex.
///
/// The exported code card does NOT read these tokens: its look is part of the
/// rendered image and must never flip with the app appearance. Export content
/// keeps using `Brand.Shadow` / `Brand.Palette.exportedCardBorder`.
enum VitrineTokens {

    // MARK: - Brand accent (violet → azure)

    /// Accent roles from `tokens/colors.css`. Base and secondary re-export the
    /// brand palette; hover/press/contrast are the interaction steps the
    /// current design uses for custom buttons and chips.
    enum Accent {
        /// `--accent` — #4F46E5 light / #7C8CFF dark (re-exported brand accent).
        static let base = Brand.Palette.accent.color
        /// The accent for app chrome (selection / hover / links / chips). It follows the
        /// user's macOS accent when they picked a specific one in System Settings →
        /// Appearance → Accent color, and otherwise — on the default "Multicolor" — keeps
        /// Vitrine's brand accent. We resolve this ourselves rather than use
        /// `Color.accentColor`/`.controlAccentColor` directly: the app ships a brand
        /// `AccentColor` asset, and `.controlAccentColor` reports the macOS *default blue*
        /// on Multicolor, which would silently drop the brand identity for everyone who
        /// never chose an accent.
        static var system: Color {
            usesSystemAccentOverride(
                accentColorValue: UserDefaults.standard.object(forKey: "AppleAccentColor"))
                ? Color(nsColor: .controlAccentColor) : base
        }
        /// Whether a stored `AppleAccentColor` value means the user chose a specific
        /// macOS accent (vs. the default "Multicolor", where the key is absent → `nil`).
        /// macOS stores an integer once set (0–6, or `-1` for graphite). Kept a pure
        /// function of the value so it is unit-testable — a `UserDefaults(suiteName:)`
        /// still cascades to the global domain, so the real key cannot be hidden in a
        /// test by removing it from a suite.
        static func usesSystemAccentOverride(accentColorValue: Any?) -> Bool {
            accentColorValue != nil
        }
        /// Text/glyph color that AppKit pairs with a selected-control/system-accent
        /// fill. This keeps custom accent-filled chips readable for every macOS
        /// accent, including yellow/graphite and high-contrast appearances.
        static let systemContrast = Color(nsColor: .selectedControlTextColor)
        /// `--accent-hover` — one step brighter on hover.
        static let hover = Brand.BrandColor(
            light: Color(hex: "#4339D4"),
            dark: Color(hex: "#8E9CFF")
        ).color
        /// `--accent-press` — one step further on press.
        static let press = Brand.BrandColor(
            light: Color(hex: "#3A30C4"),
            dark: Color(hex: "#AEB8FF")
        ).color
        /// `--accent-secondary` — the gradient's far stop (re-exported).
        static let secondary = Brand.Palette.accentSecondary.color
        /// `--accent-contrast` — text and glyphs over accent fills.
        static let contrast = Brand.BrandColor(
            light: Color(hex: "#FFFFFF"),
            dark: Color(hex: "#15161C")
        ).color
    }

    // MARK: - Surfaces (the neutral "display case")

    /// Backdrop and container fills from `tokens/colors.css`.
    enum Surface {
        /// `--stage` — preview stage + window wash (re-exported brand stage).
        static let stage = Brand.Palette.stage.color
        /// `--window` — the macOS window chrome base.
        static let window = Brand.BrandColor(
            light: Color(hex: "#ECECEE"),
            dark: Color(hex: "#1C1D24")
        ).color
        /// `--surface-card` — raised cards and popovers.
        static let card = Brand.BrandColor(
            light: Color(hex: "#FFFFFF"),
            dark: Color(hex: "#22232B")
        ).color
        /// `--surface-inset` — grouped-list inset fill.
        static let inset = Brand.BrandColor(
            light: Color(hex: "#F4F5F7"),
            dark: Color(hex: "#1A1B22")
        ).color
        /// `--surface-row` — list row fill.
        static let row = Brand.BrandColor(
            light: Color(hex: "#FFFFFF"),
            dark: Color(hex: "#25262F")
        ).color
    }

    // MARK: - Text

    /// Text tiers from `tokens/colors.css`.
    enum Text {
        /// `--text-primary` (re-exported).
        static let primary = Brand.Palette.textPrimary.color
        /// `--text-secondary` — captions, secondary labels (re-exported).
        static let secondary = Brand.Palette.textSecondary.color
        /// `--text-tertiary` — placeholders and disabled labels.
        static let tertiary = Brand.BrandColor(
            light: Color(hex: "#8A8C99"),
            dark: Color(hex: "#6F7180")
        ).color
    }

    // MARK: - Hairlines & separators

    /// Thin lines from `tokens/colors.css`. Low-opacity so they read as glass.
    enum Line {
        /// `--border` — card / preview hairline (re-exported).
        static let border = Brand.Palette.border.color
        /// `--separator` — row separators inside lists.
        static let separator = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.09),
            dark: Color(hex: "#FFFFFF").opacity(0.08)
        ).color
        /// `--control-track` — the off track behind custom toggles.
        static let controlTrack = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.16),
            dark: Color(hex: "#FFFFFF").opacity(0.18)
        ).color
        /// `--focus-ring` — the 1.5 pt accent focus stroke.
        static let focusRing = Brand.Palette.accent.color
        /// `--ring-focus` — the soft outer glow behind the focus stroke.
        static let focusGlow = Brand.Palette.accent.color.opacity(0.35)
    }

    // MARK: - Gradients (135°, topLeading → bottomTrailing)

    /// Gradient tokens from `tokens/gradients.css`. The signature and wash
    /// re-export `Brand.Gradient`; the preset gradients re-export
    /// `GradientPreset` so chips and canvases share the exact same stops.
    enum Gradients {
        /// `--grad-signature` — the violet→azure brand identity.
        static let signature = Brand.Gradient.signature
        /// `--grad-signature-wash` — 18 % wash for hero backgrounds.
        static let signatureWash = Brand.Gradient.signatureWash()
        /// `--grad-aurora` … `--grad-carbon` — the built-in canvas presets.
        static let aurora = GradientPreset.aurora.gradient
        static let ocean = GradientPreset.ocean.gradient
        static let sunset = GradientPreset.sunset.gradient
        static let forest = GradientPreset.forest.gradient
        static let night = GradientPreset.night.gradient
        static let carbon = GradientPreset.carbon.gradient
    }

    // MARK: - Spacing (4-pt scale, re-exported)

    /// `tokens/spacing.css` — identical to `Brand.Spacing`.
    enum Spacing {
        static let xxs = Brand.Spacing.xxs
        static let xs = Brand.Spacing.xs
        static let sm = Brand.Spacing.sm
        static let md = Brand.Spacing.md
        static let lg = Brand.Spacing.lg
        /// 32 pt — also the default export padding.
        static let xl = Brand.Spacing.xl
        static let xxl = Brand.Spacing.xxl
    }

    // MARK: - Corner radius (continuous style)

    /// `tokens/elevation.css` radii — re-exported plus the pill shape.
    enum Radius {
        static let sm = Brand.Radius.sm
        static let md = Brand.Radius.md
        static let lg = Brand.Radius.lg
        static let xl = Brand.Radius.xl
        /// The exported code-card corner radius.
        static let card = Brand.Radius.card
        /// `--radius-pill` — fully rounded capsules and chips.
        static let pill: CGFloat = 999
    }

    // MARK: - Shadows (app chrome only)

    /// Shadow recipes from `tokens/elevation.css`, translated for SwiftUI
    /// (`shadow(radius:)` takes half the CSS blur). These style the current designed
    /// chrome; the exported card keeps `Brand.Shadow` so renders stay
    /// byte-identical to the earlier goldens.
    enum Shadows {
        /// `--shadow-card` — subtle lift for cards inside the app chrome.
        static let card = Brand.ShadowStyle(
            color: .black.opacity(0.18), radius: 6, x: 0, y: 6)
        /// `--shadow-elevated` — the deep offset under prominent cards.
        static let elevated = Brand.ShadowStyle(
            color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
        /// `--shadow-popover` — floating panels and the menu-bar window.
        static let popover = Brand.ShadowStyle(
            color: .black.opacity(0.22), radius: 17, x: 0, y: 10)
    }

    // MARK: - Chrome component fills

    /// Component-level fills shared across the app's design system.
    /// These are the low-opacity washes the current designed chrome layers over
    /// `Surface.window` — kept here so views never spell out a raw rgba.
    enum Chrome {
        /// `.tile` — the grouped-form card fill.
        static let tile = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.035),
            dark: Color(hex: "#FFFFFF").opacity(0.04)
        ).color
        /// `.side` — the settings sidebar wash.
        static let sidebar = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.025),
            dark: Color(hex: "#FFFFFF").opacity(0.03)
        ).color
        /// `.seg` — the pill segmented-control track.
        static let segmentTrack = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.06),
            dark: Color(hex: "#FFFFFF").opacity(0.06)
        ).color
        /// `.kbd-chip` — keyboard-glyph chip fill.
        static let keyChip = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.06),
            dark: Color(hex: "#FFFFFF").opacity(0.07)
        ).color
        /// `.dfield` — bordered inline text-field fill.
        static let fieldFill = Brand.BrandColor(
            light: Color(hex: "#1A1B22").opacity(0.04),
            dark: Color(hex: "#FFFFFF").opacity(0.05)
        ).color
        /// Selected font-pill wash — the lifted accent at 12 % in both
        /// appearances (the design uses one fixed value).
        static let pillSelectedFill = Color(hex: "#7C8CFF").opacity(0.12)
        /// Selected gradient-swatch border — accent in light, white over the
        /// dark stage.
        static let swatchSelectedBorder = Brand.BrandColor(
            light: Color(hex: "#4F46E5"),
            dark: Color(hex: "#FFFFFF")
        ).color

        /// The selected segment's lift (`0 1px 3px rgba(0,0,0,0.3)`).
        static let segmentShadow = Brand.ShadowStyle(
            color: .black.opacity(0.3), radius: 1.5, x: 0, y: 1)
        /// The gradient CTA's accent halo (`0 4px 14px rgba(79,70,229,0.45)`).
        static let ctaShadow = Brand.ShadowStyle(
            color: Color(hex: "#4F46E5").opacity(0.45), radius: 7, x: 0, y: 4)
        /// The stage's floating status capsule — a fixed dark wash in both
        /// appearances (`rgba(34,35,43,0.7)` in the editor).
        static let statusCapsule = Color(hex: "#22232B").opacity(0.7)
        /// The sticky style-header drop (`0 10px 18px -14px rgba(0,0,0,0.55)`);
        /// SwiftUI has no shadow spread, so this is the closest tight underline.
        static let stickyHeaderShadow = Brand.ShadowStyle(
            color: .black.opacity(0.28), radius: 5, x: 0, y: 6)
    }

    // MARK: - Type scale (macOS-native points)

    /// `tokens/typography.css` — the UI type scale plus the default code size.
    enum FontSize {
        /// 28 — welcome / about hero.
        static let largeTitle: CGFloat = 28
        /// 17 — window titles, section heroes.
        static let title: CGFloat = 17
        /// 15 — group headers, emphasized labels.
        static let headline: CGFloat = 15
        /// 13 — the macOS control body size.
        static let body: CGFloat = 13
        /// 12 — secondary labels.
        static let subhead: CGFloat = 12
        /// 11 — captions, badges, footnotes.
        static let caption: CGFloat = 11
        /// 14 — the default code size in the editor.
        static let code: CGFloat = 14
    }
}
