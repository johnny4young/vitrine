<div align="center">

# 📸 Vitrine

### Turn code into beautiful images — straight from your menu bar.

**Vitrine** is a native macOS menu-bar app that turns code (and, later, URLs and
HTML) into gorgeous, share-ready images — in the spirit of [ray.so](https://ray.so)
and [Carbon](https://carbon.now.sh), but **native, instant, and fully local**.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange.svg?logo=swift)](https://swift.org)
[![Status](https://img.shields.io/badge/status-WIP%20·%20v0.1-yellow.svg)](docs/ROADMAP.md)

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

Works **offline**, **100% local**, no account, no server. MIT-licensed.

> ray.so (built by Raycast) is open source and is exactly the bar we hold ourselves
> to for UX and design. The difference: Vitrine is **native and always one shortcut
> away in the menu bar** — not a web page, not a Raycast command.

## The flow you'll actually use

1. **Copy** what you want to share — a snippet of code today, and URLs in Product Phase 2.
2. **Trigger Vitrine** — global hotkey (`⌘⇧S`) or the menu-bar icon.
3. **Vitrine detects the content type** and picks the renderer:
   - **Code** → format + syntax highlight → a beautiful image, using the theme and
     style you preset in **Settings** (no questions asked).
   - **URL** → detected today and deliberately deferred; Product Phase 2 will snapshot
     the page locally with `WKWebView` (see [Product Phase 2](docs/RENDER-PHASES.md)).
4. **The code screenshot lands on your clipboard**, ready to paste anywhere — or save to a file.

Two modes, one engine:

- **Quick mode** — trigger → detect → render with your saved settings → clipboard. Zero or one click.
- **Editor mode** — opens a window with live preview and controls when you want to tweak before exporting.

## Features (v0.1 target)

- 🍫 Native **menu-bar app** (`MenuBarExtra`, `LSUIElement` — no Dock icon, no app switcher).
- ⌨️ Configurable **global hotkey** (`⌘⇧S`) via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).
- 🌈 **Syntax highlighting** for 160+ languages via [Highlightr](https://github.com/raspu/Highlightr) (Highlight.js).
- 🎨 Themes (One Dark, GitHub, Night Owl, Dracula, Monokai, Solarized), gradients, window chrome, padding, fonts.
- 🖼️ **Retina PNG export** (`ImageRenderer` @2x/@3x) → clipboard or file, plus the macOS Share Sheet.
- ⚙️ **Settings** with live preview, powered by [Settings](https://github.com/sindresorhus/Settings).
- 🔒 Sandboxed, no network by default — your code **never leaves your Mac**.

See the full ticket breakdown in [**docs/ROADMAP.md**](docs/ROADMAP.md).

## Tech stack

| Layer            | Choice                                                        |
| ---------------- | ------------------------------------------------------------- |
| Language          | **Swift 6**                                                  |
| UI                | **SwiftUI** + AppKit (`MenuBarExtra`, `NSTextView`, `NSPasteboard`) |
| Highlighting      | [Highlightr](https://github.com/raspu/Highlightr)            |
| Global hotkey     | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) |
| Preferences       | [Settings](https://github.com/sindresorhus/Settings)         |
| View → image      | `ImageRenderer` (built-in)                                    |
| Project gen       | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) |

## Requirements

- macOS **14.0+** (Sonoma or later)
- **Xcode 16+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the
  `.xcodeproj` is generated, not committed.

## Getting started

```bash
git clone https://github.com/johnny4young/vitrine.git
cd vitrine

# Generate Vitrine.xcodeproj from project.yml and open it
make            # == make bootstrap → xcodegen generate → open
```

Or step by step:

```bash
make project    # xcodegen generate  → Vitrine.xcodeproj
make open       # open Vitrine.xcodeproj in Xcode
make build      # headless xcodebuild (Debug)
make test       # run the Swift Testing suite
make build-ui-tests # compile UI tests without automation permission
make test-ui    # run UI smoke tests (requires local XCTest automation permission)
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

## Project layout

```
vitrine/
├── project.yml            # XcodeGen spec — source of truth for the Xcode project
├── Makefile               # bootstrap / project / build / run helpers
├── Vitrine/               # app source (see docs/ARCHITECTURE.md)
│   ├── App/               # @main, MenuBarExtra, AppDelegate
│   ├── MenuBar/           # menu + submenus, quick-capture (no-UI mode)
│   ├── Editor/            # code editor, Highlightr wrapper, language detection
│   ├── Canvas/            # the SwiftUI view that becomes the PNG
│   ├── Export/            # ImageRenderer → PNG → clipboard / share
│   ├── Settings/          # @AppStorage settings, preferences window, themes
│   ├── Models/            # SnapshotConfig, Theme, Language, shortcuts
│   └── Resources/         # Assets, Info.plist, entitlements
└── docs/                  # full project documentation (mirrors the original spec)
```

## Documentation

Everything from the original product spec lives in [`docs/`](docs/) so you never need
to leave the repo:

- [**docs/PROJECT.md**](docs/PROJECT.md) — vision, positioning, naming, distribution, risks.
- [**docs/ARCHITECTURE.md**](docs/ARCHITECTURE.md) — menu-bar UX, user flow, modules, data model.
- [**docs/RENDER-PHASES.md**](docs/RENDER-PHASES.md) — "beyond code": OG cards, HTML/URL snapshots, and the optional web render service.
- [**docs/RELEASING.md**](docs/RELEASING.md) — signed/notarized DMG, Homebrew cask, release workflow.

> The detailed implementation spec (`docs/ROADMAP.md`, ticket-by-ticket acceptance
> criteria) is kept as a local working document and is intentionally git-ignored.

## Status

🟢 **v0.1 feature-complete.** Menu-bar app (`LSUIElement`) with global hotkey, the
live-highlight editor, WYSIWYG canvas, PNG/PDF export to clipboard/file, the macOS
share sheet, Recents history, a five-pane Settings window, launch-at-login, a privacy
manifest, a reproducible app icon, and a tagged-release pipeline (DMG + Homebrew cask).
Covered by a Swift Testing unit suite plus XCTest UI smoke tests. CI runs lint, build,
the UI-test build, and the unit tests; `make test-ui` runs locally (it needs XCTest
automation permission that GitHub-hosted runners don't grant).
The URL→screenshot path and OG cards are deliberately deferred (see RENDER-PHASES,
"Product Phase 2").

## Contributing

Themes and language tweaks are especially welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and the conventions in [AGENTS.md](AGENTS.md).

## License

[MIT](LICENSE) © johnny4young
