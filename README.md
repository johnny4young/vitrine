<div align="center">

<img src="site/public/vitrine-icon.png" alt="" width="116" height="116">

# Vitrine

### Turn code into beautiful images — straight from your menu bar.

**Vitrine** is a native macOS menu-bar app that turns code (and URLs and HTML) into
gorgeous, share-ready images — in the spirit of [ray.so](https://ray.so) and
[Carbon](https://carbon.now.sh), but **native, instant, and fully local**.

[![Website](https://img.shields.io/badge/website-vitrineframe.app-6E56CF.svg)](https://vitrineframe.app)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg?logo=swift)](https://swift.org)
[![Status](https://img.shields.io/badge/status-v0.23.0%20shipped-brightgreen.svg)](#status)

</div>

---

## Why

`Carbon.now.sh` and `ray.so` are the go-to tools for turning code into images — but
they're **web apps**: open the browser, paste, configure, export. **None of them
live in your Mac's menu bar.** A developer who shares code on X, in docs, or in
slides does it many times a week, and every second of friction adds up.

Vitrine attacks that flow head-on:

- **0 seconds to open** — always present in the menu bar.
- **Code already loaded** — read straight from the clipboard.
- **Live preview** in the editor, or a no-UI quick mode that just works.
- **`Copy` → retina PNG** on your clipboard, ready to paste into Notion, Slack, X, Keynote.

Works **offline**, **100% local**, no account, no telemetry. MIT-licensed — with an
optional [**PRO**](#vitrine-pro) tier for people who publish professionally.

> ray.so (built by Raycast) is open source and is exactly the bar we hold ourselves
> to for UX and design. The difference: Vitrine is **native and always one shortcut
> away in the menu bar** — not a web page, not a Raycast command.

## The flow you'll actually use

1. **Copy** what you want to share — a snippet of code, or a URL.
2. **Trigger Vitrine** — global hotkey (`⇧⌘S`) or the menu-bar icon.
3. **Vitrine detects the content type** and picks the renderer:
   - **Code** → format + syntax highlight → a beautiful image, using the theme and
     style you preset in **Settings** (no questions asked).
   - **URL** → snapshot the page **locally** with `WKWebView` on the direct-download
     build, with a first-use privacy disclosure (see [Rendering architecture](docs/RENDERING.md)).
4. **The screenshot lands on your clipboard**, ready to paste anywhere — or save to a file.

Two modes, one engine:

- **Quick mode** — trigger → detect → render with your saved settings → clipboard. Zero or one click.
- **Editor mode** — opens a window with live preview and controls when you want to tweak before exporting.

## Install

Requires macOS **14.0+** (Sonoma or later). Every build is signed with a
Developer ID and notarized by Apple, and updates itself through Sparkle.

### Homebrew (recommended)

```bash
brew install --cask johnny4young/tap/vitrine
```

Homebrew downloads the DMG from the latest GitHub release, verifies its
SHA-256, and moves **Vitrine.app** into `/Applications`. Upgrades arrive
in-app ("Check for Updates…"), or via `brew upgrade --cask vitrine`. The cask
also puts the [`vitrine` CLI](#command-line-renderer) on your PATH (from v0.5.0).

### Direct download

Grab `Vitrine-x.y.z.dmg` from the
[latest release](https://github.com/johnny4young/vitrine/releases/latest) (or
from [vitrineframe.app](https://vitrineframe.app)), open it, and drag **Vitrine**
into **Applications**. Each DMG ships with a `.sha256` sidecar if you want to
verify the download:

```bash
shasum -a 256 -c Vitrine-x.y.z.dmg.sha256
```

### Build from source

```bash
git clone https://github.com/johnny4young/vitrine.git && cd vitrine && make
```

See [Getting started](#getting-started) for the full developer setup.

After launch, Vitrine lives in your **menu bar** (📸) — there is no Dock icon,
by design.

## Gallery

### The app

Captured from the real build (regenerate with the opt-in screenshot tour in
[`UITests/ScreenshotTourUITests.swift`](UITests/ScreenshotTourUITests.swift)).
The whole app follows one design system — a token layer
([`Vitrine/DesignSystem/`](Vitrine/DesignSystem)) shared by every surface, in
light and dark.

<div align="center">

<img src="site/public/screenshots/editor.png" alt="The editor: glass toolbar with the gradient Copy image action, code pane, the preview floating in ambient light cast by its background, and the style inspector" width="760">

| First-run quick-start | Settings | Menu-bar panel |
| --- | --- | --- |
| <img src="site/public/screenshots/welcome.png" alt="Onboarding quick-start: numbered steps, a live sample card you can restyle, and the privacy promise" width="250"> | <img src="site/public/screenshots/settings.png" alt="Settings — Style pane with the pinned live preview, sub-tabs, and theme and font chip pickers" width="250"> | <img src="site/public/screenshots/menu-bar.png" alt="The menu-bar panel: gradient capture action, recent captures, theme chips, and explicit command rows" width="250"> |

</div>

### The exports

Every image below is **generated by Vitrine's own renderer** (`make gallery`), not a
hand-made mockup — so it's exactly what you'd export. The full launch gallery (themes,
languages, social presets, transparent backgrounds, and a high-contrast accessibility
sample) lives under [`Tests/Fixtures/Samples/`](Tests/Fixtures/Samples) and is reviewed
on every release.

<div align="center">

| Signature look (One Dark) | OpenGraph link card (1200×630) |
| --- | --- |
| <img src="Tests/Fixtures/Samples/theme-one-dark.png" alt="One Dark theme on the aurora gradient" width="380"> | <img src="Tests/Fixtures/Samples/preset-opengraph.png" alt="OpenGraph 1200×630 link-preview card" width="380"> |

| Real syntax highlighting (Python) | High-contrast / accessibility |
| --- | --- |
| <img src="Tests/Fixtures/Samples/lang-python.png" alt="Python highlighted on Dracula" width="380"> | <img src="Tests/Fixtures/Samples/a11y-high-contrast.png" alt="WCAG AA high-contrast palette" width="380"> |

| Annotated markup (counter, box, blur, arrow) | GitHub-style diff coloring |
| --- | --- |
| <img src="site/public/screenshots/annotated.png" alt="A snapshot marked up with a numbered counter, a rectangle, a blur/redaction box over a secret, an arrow, and a text callout" width="380"> | <img src="site/public/screenshots/diff.png" alt="A unified diff with + lines banded green and − lines banded red, GitHub-style, with line numbers" width="380"> |

**Full-screen TUIs** — Vitrine reconstructs the final screen (cursor moves, colors, and all), not just scrolling output. Real captures of `htop`, `lazygit`, and Neovim:

| `htop` · One Dark | `lazygit` · Dracula | `nvim` · Nord |
| --- | --- | --- |
| <img src="site/public/screenshots/terminal-htop.png" alt="htop's system monitor reconstructed as an image — CPU and memory meters, the process table, and the function-key bar" width="250"> | <img src="site/public/screenshots/terminal-lazygit.png" alt="The lazygit multi-panel git dashboard reconstructed — status, files, branches, commits, and a diff pane" width="250"> | <img src="site/public/screenshots/terminal-nvim.png" alt="A Neovim editing session reconstructed with syntax highlighting and the status line" width="250"> |

</div>

> How the gallery is generated, what it covers, and the design-QA process live in
> [**docs/DESIGN-QA.md**](docs/DESIGN-QA.md).

## Features

Vitrine does one thing — turn code into an image worth sharing — and does it without
ever leaving your Mac.

### Capture

Lives in the menu bar (`LSUIElement`, no Dock icon) and opens from anywhere with a
global hotkey (`⇧⌘S`). It reads the clipboard, detects whether you copied **code,
terminal output, a URL, or HTML**, and picks the renderer for you — one-step Quick mode
using your saved style, or the editor when you want to fine-tune.

### Beautify any image

Not just code — drop, paste, or quick-capture **any screenshot** and render it on the
same gradients, padding, and shadow. Frame it as a **macOS window**, a **browser**, or a
**MacBook / iPhone** mockup, with chrome that auto-tints to the image's own colors so it
blends in. *(Browser and device frames are [PRO](#vitrine-pro).)*

### Style

Thirteen built-in themes (plus your own), 160+ languages of real syntax highlighting,
developer fonts, and solid / gradient / image backgrounds. **Focus mode** dims
everything but the lines that matter; **diff coloring** bands `+`/`−` lines
GitHub-style; window chrome, padding, corner radius, and shadow are all yours to tune.

### Annotate

A CleanShot-style palette in the title bar — arrows (straight and **curved**), lines,
rectangles, text callouts, a highlighter, blur/redaction boxes, numbered counters,
**emoji stickers**, a **spotlight** that dims everything but the regions you draw, and a
**measure** ruler that labels the pixel span between two points. Draw them on the live
preview, move and resize with handles, undo with ⌘Z; they are baked into the export.
**Redact secrets** goes one better: one click scans the capture for API keys, tokens,
and passwords and blurs those lines for you — image *and* copyable text.

### Export & share

Retina **PNG**, **PDF**, and **HEIC** to the clipboard, a file, or the Share Sheet — sRGB
by default (Display P3 on demand), with real alpha for transparent backgrounds.
The editor's alternate copy menu can also produce highlighted RTF/HTML, a PNG data URI,
or a self-contained Markdown block with the rendered image and redaction-safe source.
The share sheet gains **Post to X / LinkedIn / Bluesky** compose targets — the image is
staged on the clipboard and the compose page opens, one paste from posting.
Destination presets cover **OpenGraph** (1200×630), an **Instagram Story**, and a
**GitHub banner**. [PRO](#vitrine-pro) adds **multi-size one-pass export**, **carousel
export** (a long snippet split into numbered 4:5 slides), and the bundled
**`vitrine` CLI** that renders the same pixels from your terminal.

### Crafted & private

One design-token system drives every surface in light and dark. Localized in English
and Spanish, updated over Sparkle on the direct-download build, and reachable from
Shortcuts and App Intents.

> [!NOTE]
> **Private by design.** Rendering is fully local and sandboxed — no account, no
> network by default, no telemetry. Your code never leaves your Mac.

**At a glance**

| Area | What you get |
| --- | --- |
| **Capture** | Menu-bar app, global hotkey, clipboard auto-detect (code · URL · HTML), Quick and editor modes |
| **Beautify** | Drop/paste any image → frame it (macOS window · browser · MacBook · iPhone) with auto-matched chrome |
| **Style** | 13 themes + custom, 160+ languages, fonts, gradient & image backgrounds, focus mode, diff coloring |
| **Annotate** | Arrows (straight · curved), lines, boxes, text, highlighter, blur, counters, spotlight, measure, stickers — with undo/redo |
| **Redact** | One-click secret scan — blurs API keys / tokens / passwords in the image *and* the copyable text |
| **Export** | Retina PNG/PDF/HEIC, Markdown/data-URI/rich-text copy, file · Share Sheet, post-to compose targets, OpenGraph · Story · GitHub-banner presets |
| **Platform** | One design system (light & dark), English + Spanish, Sparkle updates, recents |
| **PRO** | Brand Kit watermark · multi-size one-pass export · automation (`vitrine` CLI, Shortcuts/App Intents, folder batch) — optional one-time license |

<details>
<summary>Everything, in detail</summary>

- 🍫 Native **menu-bar app** (`MenuBarExtra`, `LSUIElement` — no Dock icon, no app switcher).
- ⌨️ Configurable **global hotkey** (`⇧⌘S`) via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).
- 🌈 **Syntax highlighting** for 160+ languages via [Highlightr](https://github.com/raspu/Highlightr) (Highlight.js).
- 🖥️ **Terminal output → image** — paste or drop colored terminal output (`git`, test runners, build logs) and Vitrine renders the ANSI/SGR styling (16 / 256 / truecolor, bold · italic · underline · strikethrough · inverse, plus OSC 8 hyperlinks); the palette follows your theme. The `vgrab` shell helper *(PRO)* captures a command's output with its color intact and adds a compact project, current Git branch when available, and command header so the image keeps its context when shared (`--no-context` restores an output-only capture). It also supports **full-screen TUIs** (`htop`, `vim`, `lazygit`), whose final screen Vitrine reconstructs with a cell-buffer emulator — wide CJK and emoji included — and a copyable-text sidecar can ship the output as text alongside the image. `vpane` *(PRO)* images a tmux pane's visible contents without re-running anything, and dropping an **asciinema** recording (`.cast`) replays it into the same renderer. → [`docs/TERMINAL.md`](docs/TERMINAL.md).
- 🖼️ **Beautify any image** — drop, paste, or quick-capture any screenshot (not just code) and render it on the same backgrounds, padding, and shadow, optionally wrapped in a macOS-window, browser, or MacBook / iPhone device frame. The frame chrome auto-tints to the image's top-edge color so it blends in (Light/Dark are manual overrides). Browser and device frames are PRO.
- 🧹 **Tidy indentation on paste** — pasted code is re-indented by structure (braces, JSX tags, JSON), with a Settings toggle, undo with ⌘Z, and ⌥⌘F to format on demand.
- 🎨 **13 built-in themes** (One Dark, Dracula, Nord, Tokyo Night, Gruvbox, Monokai, Solarized, GitHub / GitHub Dark, Xcode Dark, Night Owl, and light variants) plus your own custom themes, gradients, window chrome, padding, fonts.
- ✏️ **Annotate the snapshot** — a CleanShot-style tool palette in the title bar: arrows (straight and curved), lines, rectangles, text callouts, a highlighter, blur/redaction boxes, numbered counters, emoji stickers, a **spotlight** that dims everything outside the regions you draw, and a **measure** ruler that labels the pixel span between two points. Draw them on the live preview, move/resize with handles, restyle color and thickness, and undo/redo with ⌘Z.
- 🔒 **Redact secrets in one click** — scan the capture for likely API keys, tokens, passwords, and private keys (AWS, GitHub, Slack, Google, Stripe, OpenAI, JWTs, `name = value` assignments) and blur the matching lines before you share. The copyable text rider (clipboard / `--text-sidecar`) is sanitized too, so the secret can't leak through the text the image hides; terminal captures are scanned on the resolved screen.
- 🎯 **Focus & diff** — dim the lines outside your highlight, and color `+`/`−` diff lines GitHub-style (automatic for the Diff language). Plus an optional window title and tunable corner radius and shadow.
- 🖼️ **Retina PNG export** (`ImageRenderer` @2x/@3x) → clipboard or file, plus the macOS Share Sheet, with **PDF** as the scalable vector format and **HEIC** as the compact one for docs sites and wikis. Exports are **sRGB by default** (Display P3 is an explicit advanced option) and transparent backgrounds keep real alpha.
- 📣 **Post to X / LinkedIn / Bluesky** — compose targets in the share sheet: the image is staged on the clipboard and the network's compose page opens with a paste hint. One paste from posting; Vitrine sends nothing anywhere.
- 🎠 **Carousel export** *(PRO)* — split a long snippet into numbered 4:5 slides (`carousel-01.png` …) for a LinkedIn/Instagram carousel. Pick the lines per slide; the split balances so the last slide never trails, and every slide carries your style and brand mark.
- 📌 **Pinned snapshot** — pin the current render in a floating window that stays above every app and follows you across Spaces, so the error or design you're working against stays visible while you code.
- 🔤 **Copy text from image** — one click runs on-device OCR (Vision) on a beautified screenshot and puts the recognized text on the clipboard. Nothing leaves the Mac.
- 📐 **Safe-area guides** — an editor-only overlay that draws the margin platforms may crop over a fixed-size destination, with a live "lines × widest column" chip; never part of the export.
- 📝 **Developer-grade copy formats** — copy highlighted RTF/HTML, a standalone PNG data URI, or one self-contained Markdown block containing the image plus copyable fenced source. Redacted lines stay redacted in every text representation.
- 🪧 **Social cards** — compose a 1200×630 card from your code (template, theme, background) to copy, save, or share, with **Instagram Story** and **GitHub banner** export presets.
- 🌐 **Web snapshots** — render pasted **HTML** to an image, or capture a **webpage** (direct-download build) — entirely locally in WebKit, with a first-use privacy disclosure. Pick **several viewports at once** (social · desktop · Full HD · mobile · custom) and Vitrine captures each in one pass, then composes them into a shareable **responsive board** — desktop, tablet, and phone side by side for responsive QA.
- ⚙️ **Settings** — a six-pane sidebar window with a pinned live preview and chip pickers for themes, fonts, and backgrounds.
- ✨ A coherent **design system** — one token layer (colors, gradients, spacing, type) drives every surface in light and dark, and the editor stage glows with the ambient color of your background.
- 🕘 **Recents gallery** — a visual history of your captures, one click from the menu bar.
- 🚀 **First-run quick-start**, offline in-app **Help**, and a **What's New** window on upgrades.
- ⚡ **Shortcuts / App Intents** *(PRO)* — render a code image or open the editor from Shortcuts and Spotlight.
- 🔁 **Sparkle auto-updates** on the direct-download (DMG) channel — "Check for Updates…" in the menu.
- 🌍 **Localized** in English and Spanish (String Catalog), with pseudolocale and RTL layout tests.
- 🖥️ **Command-line renderer** *(PRO)* — `vitrine render input.swift --out image.png` for docs pipelines and automation, with output pixel-identical to the app (no network, screen recording, or Accessibility needed).
- 💎 **PRO power features** — [Brand Kit](#vitrine-pro) watermark (now with a scannable **QR link chip** and a **signature footer bar** placement), multi-size one-pass export, carousel export, and the automation surfaces above; the free tier loses nothing.
- 🔒 Sandboxed, no network by default — your code **never leaves your Mac**.

</details>

## Vitrine PRO

Vitrine is **open-core**: the app is and stays free and fully open source (MIT), and the
free tier loses nothing — no watermark, no resolution cap, no launch-time nags. **PRO** is
an optional **one-time** license that adds a few power features for people who publish
professionally:

- **Brand Kit** — your logo, handle, and accent color applied as a tasteful watermark to
  every export, in one click.
- **Multi-size export** — one capture rendered to every platform size (X, LinkedIn,
  OpenGraph, …) into a folder in a single pass.
- **Automation** — the `vitrine` command-line renderer, Shortcuts / App Intents, and folder
  batch rendering.

It is **honor/convenience, not anti-fork DRM**. On the Mac App Store, PRO is a StoreKit
in-app purchase; on the direct-download build, a license key activates **once** online and
the app then verifies an **offline, signed token** on every launch (the bundled CLI
re-verifies the same token), so PRO works without the network after activation. Nothing
about your code or usage is ever sent. Details: [`docs/PRO.md`](docs/PRO.md).

## Privacy

Vitrine is private by design, and that promise does not soften as the product grows:

- **Code rendering: your code never leaves your Mac.** Rendering a code image is fully
  local and on-device — no account, and no network at all on the App Store build (it ships
  sandboxed *without* the network entitlement). Rendering needs no Screen Recording or
  Accessibility permission.
- **URL capture: the requested webpage loads locally.** When a copied URL is captured,
  Vitrine loads that webpage **locally in WebKit on your Mac** and turns it into an image
  on-device. There is **no remote screenshot service** — the URL is never sent off your
  machine to be rendered. URL capture is opt-in, gated behind the network entitlement
  (present only on the direct-download build), and shows a first-use disclosure before any
  page loads. Only `http`/`https` URLs are accepted. Private and local-network hosts are
  refused; a separate default-off setting can allow only this Mac's loopback interface
  (`localhost`, `127/8`, and `::1`) for development servers. `.local`, LAN, link-local,
  metadata, and other private addresses stay blocked. The web view uses a non-persistent
  data store by default (no cookies or website data persist across captures unless you
  opt in).
- **PRO activation contacts only the license provider, once.** On the direct-download build,
  activating a PRO license makes a single online check to the license provider (Lemon
  Squeezy) to validate your key; afterward PRO is verified from an offline signed token and
  never touches the network again. Nothing about your code or usage is sent. (On the Mac App
  Store, PRO is an ordinary StoreKit purchase.)
- **No analytics, no telemetry, ever.** Code rendering, URL capture, and PRO activation
  collect, track, and transmit **no** usage data. The bundled privacy manifest declares no
  tracking and no collected data, so the App Store privacy label is **Data Not Collected**.

The permission and privacy posture is documented in
[**docs/PROJECT.md**](docs/PROJECT.md#privacy-and-permissions); the full
entitlement-by-entitlement audit table for each distribution channel is in
[**docs/PERMISSIONS.md**](docs/PERMISSIONS.md).

## Tech stack

| Layer            | Choice                                                        |
| ---------------- | ------------------------------------------------------------- |
| Language          | **Swift 6**                                                  |
| UI                | **SwiftUI** + AppKit (`MenuBarExtra`, `NSTextView`, `NSPasteboard`) |
| Highlighting      | [Highlightr](https://github.com/raspu/Highlightr)            |
| Global hotkey     | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| Auto-updates      | [Sparkle](https://sparkle-project.org) (direct-download channel) |
| View → image      | `ImageRenderer` (built-in)                                    |
| Project gen       | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |

## Requirements

- macOS **14.0+** (Sonoma or later)
- **Xcode 16+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), installed from the verified
  release asset with `./scripts/install-xcodegen.sh` — the `.xcodeproj` is generated,
  not committed.

## Getting started

```bash
git clone https://github.com/johnny4young/vitrine.git
cd vitrine
./scripts/install-xcodegen.sh
export PATH="$HOME/.local/bin:$PATH"

# Generate Vitrine.xcodeproj from project.yml and open it
make            # == make bootstrap → xcodegen generate → open
```

Or step by step:

```bash
make project    # xcodegen generate  → Vitrine.xcodeproj
make open       # open Vitrine.xcodeproj in Xcode
make build      # headless xcodebuild (Debug)
make cli        # build the `vitrine` command-line renderer
make test       # run the Swift Testing suite
make build-ui-tests # compile UI tests without automation permission
make test-ui    # run UI smoke tests (first local run prompts for automation permission)
make gallery    # (re)generate the launch-gallery design-QA samples
make format     # swift-format in place
make lint       # swift-format lint (CI gate)
make icon       # regenerate the app icon set
```

Then hit **▶︎ Run** in Xcode. Vitrine appears in the menu bar (📸). There is no Dock
icon — that's intentional (`LSUIElement`).

> **Why is `Vitrine.xcodeproj` not in the repo?** It's generated from
> [`project.yml`](project.yml) so it can never drift from the spec and never causes
> merge conflicts. Run `make project` (or `xcodegen generate`) after cloning. See
> [CONTRIBUTING.md](CONTRIBUTING.md).

## Command-line renderer

Vitrine ships a `vitrine` CLI that renders code to an image without the GUI — handy
for docs pipelines and automation. It reuses the app's exact render path, so output is
pixel-identical, and it needs no network, screen recording, or Accessibility.

```bash
make cli   # builds `vitrine` into DerivedData, next to its Fonts/ and Highlightr bundle

vitrine render input.swift --out image.png
vitrine render snippet.py --out card.png --theme dracula --preset opengraph
vitrine render notes.go   --out clear.png --transparent --scale 3
vitrine render server.go  --out night.png --background night
vitrine render query.sql  --out solid.png --background-color '#1E293B'
vitrine render app.swift --out gradient.png \
  --background-gradient '#FF453A,#FFD60A,#64D2FF' --background-angle 215
vitrine render app.swift --out photo.png --background-image landscape.png \
  --background-fit fill --background-blur 8 --background-dimming 0.35
vitrine render payload.json --out payload.png --format-code --text-sidecar
vitrine render release.swift --out branded.png --watermark '@jane · vitrine' \
  --watermark-color '#7DD3FC' --watermark-position top-left
vitrine render release.swift --out logo.png --watermark-logo brand.png \
  --watermark-position bottom-left
vitrine render release.swift --out centered.png --watermark '@jane · vitrine' \
  --watermark-position free --watermark-x 0.5 --watermark-y 0.18
vitrine render release.swift --out reviewed.png --callout 'Review this branch' \
  --callout-x 0.68 --callout-y 0.2 --callout-color '#FDE047' --callout-size 6
vitrine render release.swift --out steps.png --counter 1 \
  --counter-x 0.82 --counter-y 0.2 --counter-color '#22C55E' --counter-size 8
vitrine render release.swift --out guided.png --arrow 0.18,0.8,0.7,0.25 \
  --arrow-color '#38BDF8' --arrow-size 9
vitrine render release.swift --out underlined.png --line 0.16,0.76,0.84,0.76 \
  --line-color '#A78BFA' --line-size 10
vitrine render release.swift --out boxed.png --rectangle 0.12,0.28,0.88,0.8 \
  --rectangle-color '#FB7185' --rectangle-size 9
vitrine render release.swift --out highlighted.png --highlighter 0.12,0.42,0.88,0.54 \
  --highlighter-color '#FFD60A'
vitrine render release.swift --out obscured.png --blur-box 0.12,0.42,0.88,0.54
vitrine render release.swift --out review-map.png \
  --arrow 0.15,0.82,0.4,0.58 --arrow 0.85,0.82,0.6,0.58 --arrow-color '#38BDF8'
vitrine render --image dashboard.png --out showcase.png --background night --padding 40
vitrine render --image dashboard.png --out browser.png --frame browser \
  --frame-appearance dark --window-title 'app.example.com'
vitrine render --image dashboard.png --out device.png --frame macbook
vitrine render long-line.swift --out wrapped.png --wrap-columns 80
vitrine render snippet.swift --out compact.png --font "Fira Code" --font-ligatures \
  --font-size 12 --padding 24 --corner-radius 10 --shadow-radius 12
vitrine render diff.patch --out review.png --language diff --highlight-lines 3,7-9 \
  --focus-lines --diff-bands
vitrine render secrets.swift --out share.png --redact-secrets --sidecars all
vitrine render changelog.md --out release.png --title "Release notes" --language-badge
vitrine render snippet.swift --out card.png --sidecars all
cat Component.tsx | vitrine render --stdin --stdin-name Component.tsx --out card.png
vitrine render input.swift --out image.png --quiet --no-overwrite
vitrine render input.swift --out image.png --json --no-overwrite
vitrine render input.swift --out image.pdf
vitrine multi-size input.swift --out social-cards --presets twitter,linkedin,opengraph
vitrine multi-size input.swift --out all-sizes --presets all --sidecars all
vitrine list themes
vitrine list languages --json
vitrine list all --json
vitrine list fonts
vitrine list backgrounds
vitrine list background-fits
vitrine list frames
vitrine list frame-appearances
vitrine list watermark-positions
vitrine list formats
vitrine list profiles --json
vitrine --version
vitrine version --json
vitrine batch Sources --out docs/cards --recursive --dry-run --include-ext swift,md \
  --fail-on-empty
vitrine batch Sources --out docs/cards --recursive --include-ext swift,md --exclude-ext tmp \
  --sidecars all --fail-on-empty --fail-on-skipped --skipped-report docs/cards/skipped.json \
  --manifest docs/cards/manifest.json
vitrine render --git-diff main...HEAD --git-path Vitrine --out review.png
vitrine render --git-staged --git-context 6 --out staged-review.png
vitrine render --help
```

Defaults match the app (One Dark, JetBrains Mono, aurora background); `--quiet`
suppresses the success summary for scripts while leaving errors visible, and `--json`
prints `render`/`batch` success summaries as structured JSON (mutually exclusive with
`--quiet`). `--theme`,
`--language`, `--preset`, `--scale`, `--format` (`png`/`pdf`/`heic`/`avif`), `--profile`
(`srgb`/`p3`), `--font <family>`, `--font-ligatures`, `--no-font-ligatures`,
`--transparent`, `--background <id>`, `--background-color <hex>`,
`--background-gradient <hex,hex,...>`, `--background-angle <degrees>`,
`--background-image <path>`,
`--background-fit <fill|fit>`, `--background-blur <0...40>`,
`--background-dimming <0...1>`,
`--frame <id>`, `--frame-appearance <auto|light|dark>`,
`--watermark <text>`, `--watermark-logo <path>`, `--watermark-color <hex>`,
`--watermark-position <corner|free>`,
`--watermark-x <0...1>`, `--watermark-y <0...1>`,
`--callout <text>`, `--callout-x <0...1>`, `--callout-y <0...1>`,
`--callout-color <hex>`, `--callout-size <2...28>`,
`--counter <1...99>`, `--counter-x <0...1>`, `--counter-y <0...1>`,
`--counter-color <hex>`, `--counter-size <2...28>`,
`--arrow <x1,y1,x2,y2>`, `--arrow-color <hex>`, `--arrow-size <2...28>`,
`--line <x1,y1,x2,y2>`, `--line-color <hex>`, `--line-size <2...28>`,
`--rectangle <x1,y1,x2,y2>`, `--rectangle-color <hex>`,
`--rectangle-size <2...28>`, `--highlighter <x1,y1,x2,y2>`,
`--highlighter-color <hex>`, `--blur-box <x1,y1,x2,y2>`, style controls
(`--font-size`, `--padding`, `--wrap-columns`, `--format-code` (alias `--tidy`),
`--corner-radius`, `--shadow-radius`, `--line-numbers`, `--no-chrome`, `--shadow`,
`--no-shadow`, `--highlight-lines <spec>`, `--redact-lines <spec>`,
`--redact-secrets`, `--focus-lines`, `--no-focus-lines`, `--diff-bands`,
`--no-diff-bands`), and the header controls
(`--window-title`, `--filename`, `--title`, `--caption`, `--language-badge`) override
individual choices. For single-file `render`, a known
`--out` extension (`.png`, `.pdf`, `.heic`, or `.avif`) selects the matching format when
`--format` is omitted; if both are present, they must agree so scripts never write
mislabeled artifacts. With `--stdin`, `--stdin-name <name>` supplies a filename hint
for extension-based language inference and default metadata without reading that file.
`--git-diff <revision-range>` loads a revision diff from the current local repository;
`--git-staged` selects only changes already in the index. Both work with `render` and
`multi-size`; repeatable `--git-path <path>` values narrow them to selected paths, while
`--git-context <0...100>` controls unchanged lines around each hunk. Vitrine invokes
`/usr/bin/git` directly without a shell, disables pagers,
external diff drivers, textconv, and color, places pathspecs after `--`, and rejects
empty output or stops Git when output exceeds 5 MB. Stable prefixes and context keep
captures independent of global Git presentation settings. Paths are literal, prompts
are disabled, and partial clones never fetch missing objects, keeping the operation
offline. Diff syntax and GitHub-style bands are selected automatically unless
`--language` or `--no-diff-bands` overrides them.
`--format-code` uses Vitrine's dependency-free, language-aware indentation tidy before
rendering; the formatted source is also used by sidecars and secret scanning so every
artifact describes the same visible code.
`--background-gradient` builds a custom gradient from two or more comma-separated
RGB/RGBA colors, spaced evenly across the canvas. `--background-angle` selects a
direction from 0 through 360 degrees and defaults to 135; custom gradients are mutually
exclusive with preset, solid, and transparent backgrounds.
`--background-image <path>` uses a local image for the canvas in both `render` and
`batch`. Vitrine imports it once per invocation into an isolated temporary store,
reuses it for every batch output, and removes the copy when the command exits; the
source image and the app's persistent background library remain unchanged.
Use `--background-fit` to choose edge-to-edge cropping or whole-image fitting,
`--background-blur` for a 0–40 point local blur, and `--background-dimming` for a
normalized dark overlay. These modifiers require `--background-image`; their bounds
match the editor and invalid values fail before any output is written.
`--watermark <text>` and `--watermark-logo <path>` add text, a local image, or both
to a deterministic badge through the same render-core overlay as Brand Kit. The logo
is loaded once per invocation and its source file remains unchanged.
`--watermark-color <hex>` changes the text tint and
`--watermark-position <corner|free>` selects one of the ids printed by
`vitrine list watermark-positions`; placement requires watermark text or a logo, while
color requires visible text.
The `free` placement additionally requires both normalized coordinates through
`--watermark-x` and `--watermark-y`, making scripted placement deterministic while the
four corner placements keep their existing behavior.
`--callout <text>` adds one deterministic text pill through the same normalized
annotation layer as the editor. It defaults to the canvas center and the editor's red
annotation style; optional x/y coordinates move its anchor, while color and size tune
its appearance. Coordinates must be supplied together, and every modifier requires
visible callout text.
`--counter <1...99>` adds one numbered badge through the same annotation layer. It
defaults to the canvas center and editor annotation style; optional paired coordinates,
fill color, and size keep scripted walkthrough steps deterministic and legible.
`--arrow <x1,y1,x2,y2>` draws a straight arrow from a normalized canvas tail to its
head through the editor annotation renderer. Repeat the flag to compose several arrows;
optional color and size apply to every arrow and use the same fixed-sRGB and stroke
ranges as the editor. Zero-length or out-of-canvas segments are rejected rather than
silently producing an invisible mark.
`--line <x1,y1,x2,y2>` draws a straight segment between normalized canvas points and
is repeatable. Its shared color and size use the editor's fixed-sRGB and stroke ranges;
malformed, out-of-canvas, or zero-length segments fail before rendering.
`--rectangle <x1,y1,x2,y2>` is repeatable and outlines each region between normalized
opposite corners. Shared color and size match the editor toolbar; collapsed width or
height is rejected so every successful command produces visible boxes.
`--highlighter <x1,y1,x2,y2>` is repeatable and draws the editor's translucent marker
fill across each normalized region. Its optional shared color uses fixed-sRGB input,
while collapsed width or height is rejected before rendering.
`--blur-box <x1,y1,x2,y2>` is repeatable and visually obscures normalized regions using
the editor's blur compositor. It does **not** sanitize the source or copyable sidecars; use
`--redact-lines` or `--redact-secrets` when sensitive text must be removed. Collapsed
width or height is rejected before rendering.
`--image <path>` beautifies a local image through the same canvas as the editor. The
source is decoded locally, copied only into an invocation-scoped temporary store, and
removed when the command exits; it is never added to Vitrine's persistent image library.
Use `--frame <id>` to wrap it in one of the frames printed by `vitrine list frames`;
`--frame-appearance <auto|light|dark>` controls the chrome and requires a frame other
than `none`. `--window-title` is available with the `macos-window` and `browser` frames.
Code-only controls and source sidecars are rejected for image input instead of silently
doing nothing, while canvas, background, export, shadow, frame, and watermark controls
remain available.
`--no-overwrite` (alias `--no-clobber`) refuses to replace
existing image or sidecar outputs; in `batch`, existing targets are reported as
skipped so the remaining new cards can still be produced. `--text-sidecar`,
`--markdown-sidecar`, `--html-sidecar`, or `--sidecars all` write copyable source
beside the image for accessible docs, README, or web embeds; rows selected with
`--redact-lines` or detected by `--redact-secrets` are replaced with `[redacted]` in
every sidecar so hidden secrets do not leak through copyable text. `vitrine batch --recursive`
walks nested folders and mirrors their relative paths under the output folder; `--dry-run`
scans and decodes the matching
inputs without writing images or sidecars. `--include-ext <list>` and
`--exclude-ext <list>` let docs pipelines pre-filter known source extensions before
loading files. Add `--fail-on-empty` when CI should fail if those filters leave no
renderable inputs, `--fail-on-skipped` when CI should fail if any unreadable or non-text
file was skipped, and `--skipped-report <json>` to write a parseable skipped-files
artifact. `--manifest <json>` writes a positive manifest of rendered outputs (or
planned outputs during `--dry-run`) with relative image paths, requested sidecar paths,
and dimensions when available. When a batch contains same-stem files such as
`Widget.swift` and `Widget.ts`, only that colliding group preserves the input extension
(`Widget.swift.png`, `Widget.ts.png`) so one artifact never overwrites the other.
`--style-preset <id>` applies one of the app's immutable built-in visual presets after
destination sizing and before explicit style flags. Run `vitrine list style-presets`
to discover deterministic ids; user presets are intentionally excluded so CI does not
depend on machine-local settings.
`--canvas-size <width>x<height>` pins an exact logical canvas between 64 and 2048 points
per axis, overriding a destination preset's dimensions while retaining its style and
recommended scale. The explicit `--scale` multiplier determines final pixel dimensions.
`vitrine multi-size <input> --out <folder>` loads one code or stdin source once and
fans it out through destination presets using stable `vitrine-<preset-id>.<format>`
filenames. It exports every preset by default; `--presets <id,id,...>` narrows the set
using ids from `vitrine list presets`, while `--presets all` is the explicit full-catalog
form. Each destination pins its own dimensions and scale, so multi-size rejects the
singular `--preset`, `--canvas-size`, and `--scale` controls. Style, metadata, annotation,
watermark, format, profile, sidecar, and no-overwrite options still apply to every output;
`--no-overwrite` preflights the complete set before rendering so an existing artifact
cannot leave a partially updated export.
`vitrine list <all|themes|languages|presets|style-presets|fonts|backgrounds|background-fits|frames|frame-appearances|watermark-positions|formats|profiles> [--json]` prints
the local render catalogs so scripts can discover valid choices without scraping docs;
`vitrine list all --json` returns one object containing every catalog.
`vitrine --version` / `vitrine version --json` reports the installed CLI version before
AppKit initialization or the PRO render gate, which makes CI install checks cheap.

The CLI ships **inside the app bundle**
(`Vitrine.app/Contents/MacOS/vitrine-cli`), so a [Homebrew install](#install)
symlinks it onto your PATH as `vitrine` automatically (from v0.5.0). With a
DMG install, use **Settings ▸ General ▸ Command-line tool ▸ Install…** — or
link it yourself:

```bash
sudo ln -sf '/Applications/Vitrine.app/Contents/MacOS/vitrine-cli' /usr/local/bin/vitrine
```

When building from source (`make cli`), the dev binary lands in DerivedData as
`vitrine-cli` next to its `Fonts/` folder and `Highlightr_Highlightr.bundle` —
keep them adjacent if you relocate it. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) ("Command-line renderer") for the
hosting strategy and bundling details.

## Project layout

```
vitrine/
├── project.yml            # XcodeGen spec — source of truth for the Xcode project
├── Makefile               # bootstrap / project / build / test / gallery helpers
├── Vitrine/               # app source (see docs/ARCHITECTURE.md)
│   ├── App/               # @main, MenuBarExtra scene, AppDelegate, main menu, window controllers
│   ├── MenuBar/           # status-item menu + quick capture (no-UI mode)
│   ├── Onboarding/        # first-run quick-start
│   ├── Editor/            # code editor, ambient-light stage, inspector, language detection
│   ├── Canvas/            # the SwiftUI views that become the exported image
│   ├── Rendering/         # capture input → code render pipeline
│   ├── WebRendering/      # local URL/HTML snapshots (WebKit, on-device)
│   ├── SocialCards/       # social-card composition
│   ├── Export/            # ImageRenderer → PNG/PDF → clipboard / file / share
│   ├── Recents/           # capture history + gallery window
│   ├── Help/              # offline Help + What's New release notes
│   ├── Feedback/          # capture HUD, notifications, diagnostics bundle
│   ├── Settings/          # six-pane Settings window, presets, custom themes
│   ├── Pro/               # open-core PRO gate: entitlements, StoreKit + license providers, Brand Kit, paywall
│   ├── DesignSystem/      # token layer (VitrineTokens) + shared chrome components
│   ├── AppIntents/        # Shortcuts / App Intents surface
│   ├── Updates/           # Sparkle auto-update integration (DMG channel)
│   ├── Services/          # macOS Services registration
│   ├── CLI/               # render core shared with the CLI target
│   ├── Models/, State/, Support/   # config, themes, persistence, logging
│   └── Resources/         # assets, Info.plist, entitlements, String Catalog
├── VitrineCLI/            # the `vitrine` command-line renderer target
├── Tests/                 # Swift Testing unit suite + golden/gallery fixtures
├── UITests/               # XCTest UI smokes + opt-in screenshot tour
├── site/                  # Astro static website (semantic HTML + vanilla CSS/JS)
└── docs/                  # current product, architecture, privacy, and release docs
```

## Documentation

The repository keeps current product, architecture, privacy, and release documentation
in [`docs/`](docs/):

- [**CHANGELOG.md**](CHANGELOG.md) — the complete, versioned change history ([Keep a Changelog](https://keepachangelog.com)).
- [**docs/PROJECT.md**](docs/PROJECT.md) — vision, positioning, naming, distribution, risks.
- [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md) — menu-bar UX, user flow, modules, data model.
- [**docs/PRO.md**](docs/PRO.md) — the PRO subsystem: the open-core gate, per-build providers, Brand Kit, multi-size export, and automation.
- [**docs/ACTIVATION.md**](docs/ACTIVATION.md) — direct-download PRO activation runbook: keypair generation, build-time key injection, and the Lemon Squeezy product.
- [**docs/RENDERING.md**](docs/RENDERING.md) — how every supported input reaches the local render and export pipeline.
- [**docs/SCREEN-CAPTURE.md**](docs/SCREEN-CAPTURE.md) — why arbitrary screen/window capture is outside the product boundary.
- [**docs/PERMISSIONS.md**](docs/PERMISSIONS.md) — every entitlement with its reason, user-facing behavior, and App Store impact by channel.
- [**docs/DESIGN-QA.md**](docs/DESIGN-QA.md) — the generated launch gallery and the design-QA process.
- [**docs/RELEASING.md**](docs/RELEASING.md) — signed/notarized DMG, Homebrew cask, release workflow.

## Status

🟢 **v0.23.0 is the latest published release.** Everything under [Features](#features) is built and
driven by one design-token system ([`Vitrine/DesignSystem/`](Vitrine/DesignSystem)) in
light and dark. It is covered by a Swift Testing unit suite plus XCTest UI smokes; CI
runs lint, build, the unit tests, and the full UI suite on GitHub's hosted macOS runners
(which pre-authorize XCTest UI automation — see [docs/RELEASING.md](docs/RELEASING.md)).
The complete, versioned history lives in [CHANGELOG.md](CHANGELOG.md), and every release
also ships an in-app **What's New**.

The main branch also contains the work listed under **Unreleased** in the changelog. It
is implemented and tested but is not a published version until the release workflow
produces a tagged artifact.

Two explicit product boundaries — no arbitrary screen/window capture and no dependency
on a hosted web-render service — are documented in
[docs/SCREEN-CAPTURE.md](docs/SCREEN-CAPTURE.md) and
[docs/RENDERING.md](docs/RENDERING.md).

## Contributing

Themes and language tweaks are especially welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and the conventions in [AGENTS.md](AGENTS.md). Usage questions follow
[SUPPORT.md](SUPPORT.md), community participation follows
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and security issues go privately through
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © johnny4young
