# Vitrine — Roadmap & Tickets

> In-repo copy of the implementation plan. Ticket IDs keep the original `CS-0xx`
> prefix for continuity with the spec.

## Render phasing (one project)

- **Phase A — Apple-native core (v0.1):** code → image (tickets CS-001 … CS-012).
- **Phase B — Apple-native extension (v0.2+):** OG / social-card templates with the
  same `ImageRenderer`; HTML/URL snapshots with `WKWebView`. Absorbs ~80% of the old
  "ShotAPI" proposal inside the Apple ecosystem, local and serverless.
- **Phase C — web surface (optional, future):** a render microservice (Satori +
  Playwright) **only** if a real need for a programmatic API, public URL sharing, or
  non-Apple consumers appears. A fallback, never a dependency of the core.

See [RENDER-PHASES.md](RENDER-PHASES.md) for the full analysis.

---

## Tickets — implementation order

### Phase 1 — Functional skeleton

- **CS-001 · Xcode + MenuBarExtra** — menu-bar icon; `LSUIElement = YES` (no Dock, no
  app switcher); click opens the menu. ✅ *scaffolded*
- **CS-002 · Global hotkey** — `⌘⇧S` opens quick mode or the editor from any app;
  configurable in Preferences. *(KeyboardShortcuts name + handler wired in scaffold.)*
- **CS-003 · Editor with syntax highlight** — `NSTextView` with real-time highlight
  (100 ms debounce), no autocorrect, monospaced font, Tab = 4 spaces.
- **CS-004 · Language picker + auto-detect** — detection on paste; manual override;
  recents first.

### Phase 2 — Canvas & preview

- **CS-005 · SnapshotCanvas** — the exported SwiftUI view is a 1:1 preview of the
  final image; hardcoded gradients; instant updates.
- **CS-006 · Customization controls** — language, theme (6, with a color chip),
  padding (16–64), font size (10–20), background, chrome and shadow toggles.

### Phase 3 — Export

- **CS-007 · Export to PNG + clipboard** — @2x/@3x retina; `Copy` < 500 ms; `⌘C`
  copies; pasteable into Notion/Slack/X/Keynote.
- **CS-008 · macOS Share Sheet** — AirDrop, Mail, Messages, Notes; same image as
  `Copy`; works offline.

### Phase 4 — Menu bar, recents & settings

- **CS-009 · Menu-bar menu with submenus + quick mode** *(replaces the old StoreKit/IAP
  ticket)* — `MenuBarExtra(.menu)` with **Recents ▸** and **Theme ▸** submenus; a "New
  capture from clipboard" action that **detects the content type** (code → highlighted
  image using saved settings; URL → screenshot via Phase B) and does
  clipboard→image→clipboard with no UI; **configurable output** (auto-copy vs manual,
  or save); history of the last 10 captures.
- **CS-010 · Settings window (with live preview)** — tabs: General (hotkey, launch at
  login); **Style** (theme, syntax highlight, font, padding, background, chrome) **with
  live preview**; **Output** (auto vs manual copy, save to file, 1x/2x/3x resolution,
  PNG/PDF format); **Input** (treat URLs as screenshot on/off); About (version, GitHub
  links). No Pro tab.

### Phase 5 — OSS distribution

- **CS-011 · Privacy + sandbox + notarization** — `NSPasteboardUsageDescription`;
  `PrivacyInfo.xcprivacy` (only `NSPrivacyAccessedAPICategoryUserDefaults`, no data
  collection); App Sandbox without `network.client`; Hardened Runtime + notarization
  for signed distribution.
- **CS-012 · OSS release** — GitHub release with a signed + notarized DMG (Sparkle
  auto-update); Homebrew cask (`brew install --cask vitrine`); README with a demo GIF.
  A free App Store build is optional and out of scope for v0.1.

---

## UX targets

- Highlight debounce ≤ 100 ms.
- `Copy` < 300 ms (spec also notes < 500 ms as the export ceiling).
- No onboarding; empty state "Paste or type code…".
- Dark mode default (One Dark).

---

## Backlog (v0.2+)

- Drag & drop a file (`.swift`, `.ts`, `.go`…) → auto-load and detect language.
- Custom themes (own color scheme) and a full color-picker background.
- Optional line numbers; optional file title.
- Share to X/Twitter with pre-filled text.
- MP4/GIF animations and multi-snippet layouts (now OSS features, no longer Pro IAP).
- Zed integration (select code + hotkey → app).
- PastePilot integration (see [PROJECT.md](PROJECT.md)).
- iOS/iPadOS version (Share Extension).
