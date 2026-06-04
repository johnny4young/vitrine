# Vitrine — Project Overview

> This document is the canonical, in-repo copy of the product vision. It mirrors the
> original Notion spec so the project is fully self-contained — you should never need
> to open Notion to understand the "why".

**Vitrine** is an open-source (MIT) macOS menu-bar app that turns code into beautiful
images, in the style of [ray.so](https://ray.so) and Carbon — but native, instant,
and local. It consolidates into a **single project** what were previously two
separate ideas:

- the **native app** (formerly "Codeshot"), and
- the **render layer** (formerly "ShotAPI").

Code images today; OG / social cards and HTML/URL snapshots as an Apple-native
extension; an optional web API only as a far-future, well-scoped phase.

- **Stack:** Swift 6 + SwiftUI + AppKit + Highlightr
- **Distribution:** OSS on GitHub (MIT) · Homebrew cask · free App Store (optional, post-v0.1)
- **Monetization:** none for now — the goal is to build the best tool and use it daily.
- **Repo:** `johnny4young/vitrine` (personal account, no organization)
- **v0.1 estimate:** ~6 weeks part-time

## The name

"Codeshot" was a working title — it collides with an existing Mac App Store app from
2020. **Vitrine** (evoking *vitrine* / a display case — showing off your code) was
chosen because it is clean in the code-screenshot / dev-tools space and memorable.

- Repo: `johnny4young/vitrine` — personal account, **no organization** for now.
- Homebrew cask and a `.app` domain are **deferred** — not now.
- Selection criteria for an OSS name: available as GitHub org/repo, Homebrew cask, and
  `.app` domain; easy to spell; memorable.
- Other candidates considered: Snapcode, Snipframe, Codecast, Codepost, Showcode,
  Glance, Framed, Snippetly.

## What it is and why

`Carbon.now.sh` and `ray.so` dominate "code → image", but they are **web apps**: open
the browser, paste, configure, export. **None live in the Mac menu bar.** Developers
who share code on X, in documentation, or in slides do it many times a week — every
second of friction matters.

Vitrine targets that flow: **0 seconds to open** (always in the menu bar), the code
**already pasted** from the clipboard, live preview, and `Copy` → retina PNG on the
clipboard. Works offline, fully local, no account, no server.

ray.so (by Raycast) is open source and is exactly the UX/design quality bar we aim
for. The difference: Vitrine is **native and always available in the menu bar** — not
a web app, not a Raycast command.

**Target user:** developers who publish technical content on X/Twitter, LinkedIn,
Substack, or who write internal documentation.

### Why open source (and unmonetized for now)

- The goal is to build the best tool and use it daily — not to generate revenue.
- MIT on GitHub: anyone can build it and contribute new themes and languages.
- Frictionless distribution: Homebrew cask + signed releases. If it ever reaches the
  App Store, it would be free.
- Less legal/marketing surface: no competing for Store keywords. A distinctive name
  still helps discoverability.

## References & inspiration

| Tool                  | Type                  | What we take                                                      |
| --------------------- | --------------------- | ---------------------------------------------------------------- |
| [ray.so](https://ray.so)            | Web (Raycast, OSS)    | The UX/design bar, theme set, simplicity                         |
| [Carbon.now.sh](https://carbon.now.sh) | Web                   | The classic: window chrome, gradients, clean export              |
| CodeSnap / Codeimg    | Extension / Web       | Variants; they confirm demand for the format                     |
| Codeshot (Sarun, 2020) | Native Mac app        | Validated the native menu-bar format, but abandoned → the old working title |

## Distribution (OSS)

- **Repo:** `johnny4young/vitrine` — personal account, **no organization** for now.
- **GitHub releases** — signed + notarized DMG, Sparkle auto-update.
- **Homebrew cask** — later (a key channel for devs); not now.
- **`.app` domain** — deferred, not now.
- **Product Hunt / Show HN / r/macapps / r/swift** — at launch; the app generates its
  own visual content.
- **App Store (free)** — optional, post-v0.1, only for discoverability.

## Risks & mitigations

| Risk                                              | Likelihood | Mitigation                                                                                  |
| ------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------- |
| Weak name / discoverability                        | Medium     | Pick a distinctive name; validate GitHub org, Homebrew cask, and `.app` domain before branding |
| Raycast / ray.so ships something equivalent        | Medium     | A native menu-bar app needs no Raycast; differentiate on speed and output quality           |
| Breaking changes in `NSPasteboard` / `ImageRenderer` | Low        | Support only stable macOS (14+); CI against macOS beta                                       |
| OSS maintenance (issues / PRs)                     | Medium     | Tight scope; open theme/language contributions; a clear CONTRIBUTING                         |

## Future: PastePilot integration

[PastePilot — Smart Clipboard] is the user's other Apple/SwiftUI project (a clipboard
manager with history and sync). Natural synergy:

- From the PastePilot history: a "Convert to image with Vitrine" action on any copied snippet.
- A shared App Group / URL scheme between both apps (both are native Swift/SwiftUI).
- **Not a dependency for v0.1** — a future hook once both are stable. Parked, non-blocking.
