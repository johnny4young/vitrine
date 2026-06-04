# Vitrine — Visual Design System (CS-036)

> Vitrine should feel like a polished **display case**, not a generic settings app. The
> app chrome and the exported images share one recognizable identity. This document is
> the contract for that identity: the tokens, the brand vocabulary, and the do/don't
> rules every contributor follows.

The tokens live in [`Vitrine/DesignSystem/`](../Vitrine/DesignSystem). They are the single
source of truth — views read them instead of hardcoding numbers or colors.

## Brand identity

- **Name:** Vitrine (French for *display case / showcase*).
- **Signature color:** a violet → azure accent (`Brand.Palette.accent` →
  `Brand.Palette.accentSecondary`).
- **Signature gradient:** `Brand.Gradient.signature` (violet → azure, top-leading to
  bottom-trailing). The export preset `GradientPreset.aurora` uses the *same* colors and
  direction, so a rendered screenshot is unmistakably "Vitrine". `aurora` is the default
  canvas background.
- **App glyph:** one SF Symbol, named once in `Brand.symbolName` (`camera.viewfinder`).
  The menu-bar extra, the About pane, and every empty state render this same symbol via
  `BrandMark`, so the mark never drifts between surfaces.
- **Silhouette:** soft, continuous rounded rectangles; thin, low-opacity strokes that
  read as glass rather than heavy outlines; offset shadows for gentle elevation.

## Tokens

All tokens are namespaced under `Brand` (see `DesignTokens.swift`).

| Group | Token | Value | Use |
| --- | --- | --- | --- |
| Spacing | `Brand.Spacing.xxs … .xxl` | 4 / 8 / 12 / 16 / 24 / 32 / 48 | gaps, padding, stacks |
| Radius | `Brand.Radius.sm … .xl` | 6 / 10 / 14 / 20 | chips, previews, panels, framing |
| Radius | `Brand.Radius.card` | 8 | the code card (default `SnapshotConfig.cornerRadius`) |
| Stroke | `Brand.Stroke.hairline` / `.focus` | 1 / 1.5 | borders, focus rings |
| Shadow | `Brand.Shadow.card` | blur 12, y 6, 18% black | in-app cards/thumbnails |
| Shadow | `Brand.Shadow.elevated` | blur 20, y 8, 35% black | the exported code card |
| Surface | `Brand.Surface.glass` / `.raised` | `Material.bar` / `.regular` | translucent chrome / raised cards |
| Color | `Brand.Palette.*` | see below | accent, stage, text, border |

### Color palette and appearances

Every `Brand.BrandColor` carries explicit **light**, **dark**, **light high-contrast**,
and **dark high-contrast** variants. Use `.color` in views — it resolves the right
variant for the current appearance automatically. The accent and neutral stage are also
mirrored in the asset catalog (`AccentColor`, `BrandStage`) with the same four variants.

| Token | Role |
| --- | --- |
| `accent` / `accentSecondary` | brand accent + gradient far stop |
| `stage` | the neutral backdrop behind previews (the "display case") |
| `textPrimary` / `textSecondary` | body and caption text on app surfaces |
| `border` | hairline border for cards and previews |

Contrast is enforced by tests (`Tests/DesignTokenTests.swift`): primary text on the stage
clears WCAG **AA (4.5:1)** and secondary text clears at least **AA-large (3:1)** in all
four appearances, and high-contrast never lowers the ratio.

## Do / Don't

**Spacing & radii**

- ✅ Do: `.padding(Brand.Spacing.lg)`, `RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)`.
- ❌ Don't: `.padding(24)`, `RoundedRectangle(cornerRadius: 10)`. Bare numbers drift over
  time and break the rhythm.

**Color**

- ✅ Do: `.foregroundStyle(Brand.Palette.textSecondary.color)`; use `.tint` / semantic
  system colors for standard controls so they stay macOS-native.
- ❌ Don't: invent one-off hex colors in a view (e.g. `Color(hex: "#5B5D6B")`). Add a
  semantic token instead, or reuse an existing one.
- ❌ Don't: hardcode a single color for both light and dark. Use a `BrandColor` so every
  appearance — including high contrast — is covered.

**Brand mark & gradient**

- ✅ Do: render the app glyph with `BrandMark`, and reach for `Brand.Gradient.signature`
  when you want the identity to show (hero fills, empty states).
- ❌ Don't: reference `"camera.viewfinder"` directly or paste the gradient stops inline.
  Name them once (`Brand.symbolName`, `Brand.Gradient`) so surfaces can't diverge.

**Native first**

- ✅ Do: keep standard macOS controls (`Form`, `Picker`, `Toggle`, `.formStyle(.grouped)`)
  and let tokens style the *surfaces around* them.
- ❌ Don't: reskin native controls into custom buttons just to apply brand color. The
  brand shows in layout, surfaces, the mark, and exports — not by fighting AppKit.

**Materials**

- ✅ Do: use `Brand.Surface.glass` / `.raised` (SwiftUI `Material`) for translucent
  chrome so vibrancy and Reduce Transparency are respected by the system.
- ❌ Don't: fake glass with a fixed translucent `Color`; it ignores accessibility
  settings and looks wrong against different desktops.

## Visual QA checklist

Run before shipping any change that touches UI chrome, the canvas, or exports:

- [ ] App chrome uses tokens for repeated spacing, radii, shadows, and accent — no new
      bare numbers or one-off hex colors (grep the diff).
- [ ] A rendered screenshot (run the **Sample gallery** test, or use the app) reads as
      "Vitrine": the `aurora` preset and accent share the brand vocabulary.
- [ ] Light mode and Dark mode both look correct (toggle in System Settings ▸ Appearance).
- [ ] Increase Contrast on (System Settings ▸ Accessibility ▸ Display) keeps text legible
      and borders visible; nothing washes out.
- [ ] The menu-bar symbol, the About pane mark, and empty states show the same glyph.
- [ ] Empty editor state shows the brand mark plus a "Paste Code" action.
- [ ] Native controls still feel native — no reskinned `Picker`/`Toggle`/buttons.
- [ ] `make lint && make build && make test` are green (contrast + token tests included).
