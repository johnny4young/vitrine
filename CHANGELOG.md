# Changelog

All notable changes to Vitrine are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Vitrine also ships a curated **What's New** for each release
(`Vitrine/Help/ReleaseNotes.swift`); this file is the fuller, developer-facing
history behind those in-app highlights. A unit test keeps the newest entry here in
lockstep with the shipped `MARKETING_VERSION` and the bundled notes, so the three
can never drift.

## [Unreleased]

## [0.8.0] - 2026-06-16

Introduces **Vitrine PRO** (open-core), grows web capture into multi-resolution
"responsive boards", and folds in a broad security / performance / UX audit pass.

### Added

- **Vitrine PRO (open-core).** An optional one-time license unlocks **Brand Kit**
  (your logo, handle, and accent color as a watermark on every export),
  **multi-size one-pass export** (one capture → every platform size into a folder),
  and **automation** (the `vitrine` CLI, Shortcuts, and folder batch rendering). The
  free tier loses nothing, and gating lives only at the edges — the render core and
  golden outputs are byte-for-byte unchanged. (Direct-download license activation
  goes live in a follow-up.)
- **Multi-resolution web capture.** Pick several viewports and Vitrine captures each
  and composes them into a deterministic "responsive board" image (direct-download
  build).
- **"That looks like a URL" → Open Web Snapshot.** Copying a URL now offers to open
  the Web Snapshot window prefilled with it, instead of a dead-end notice.

### Changed

- Hardened the URL-capture SSRF defense to refuse resolver-equivalent host forms
  (`127.1`, `0x7f000001`, IPv4-mapped IPv6, zone IDs, trailing-dot FQDNs) on the
  entry URL **and** on post-redirect navigation targets.
- Faster across surfaces: syntax-highlight theme + tokenization memoization, a
  no-op-path short-circuit in color-profile normalization, a cheaper watermark diff,
  a cached brand logo, and downsampled Web Snapshot filmstrip thumbnails.
- Recents rows in the menu bar are now proper buttons (better VoiceOver and keyboard
  reach).
- Internal refactors with no behavior change: the web-capture settings moved into a
  focused `WebCaptureSettings` store, and the Brand Kit controls into their own
  Settings section.

### Fixed

- The File-menu Save / Share / Copy now apply the Brand Kit watermark, matching the
  editor toolbar.
- The Web Snapshot "network-quiet" wait no longer fails a capture when a page never
  goes quiet within its budget — it snapshots best-effort.
- A "Reset all settings" now clears the Brand Kit; the accent color can be reset to
  its legible default; a failed logo import is surfaced inline; and the "What's New"
  window footer no longer crowds its content.

## [0.7.0] - 2026-06-14

The first release tracked in this changelog. It folds in the editor polish
accumulated since 0.6.0.

### Added

- **Annotations.** A CleanShot-style tool palette in the editor's title bar —
  arrows, lines, rectangles, text callouts, a highlighter, blur/redaction boxes,
  and numbered counters — drawn directly on the live preview, moved and resized
  with handles, and baked into the exported image.
- **Undo/redo** for annotations (⌘Z / ⇧⌘Z), scoped so it never steals the code
  editor's own undo while you type.
- **Focus mode** dims the lines outside the current highlight.
- **Diff coloring** bands `+` lines green and `−` lines red, GitHub-style;
  choosing the Diff language turns it on automatically.
- **Canvas controls:** an optional window title, plus corner-radius and shadow
  sliders.
- **Export presets** for an Instagram Story (1080×1920) and a GitHub README
  banner, a View ▸ Theme quick menu, and searchable theme and font pickers.
- **Image background from a URL** (direct-download build only).
- A **“Close the editor after copying”** setting, on by default.

### Changed

- The editor title bar is now a unified toolbar carrying the language picker, the
  annotation tools, and the export actions, with the traffic lights centered to
  match.
- The inspector no longer has an annotations section — the title-bar palette owns
  annotation editing.

## [0.6.0] - 2026-06-13

### Added

- **Social cards:** compose a 1200×630 card from your code — pick a template,
  theme, and background, then copy, save, or share it.
- **Web snapshots:** render pasted HTML to an image locally in a new Web Snapshot
  window, with no network.
- **URL capture** (direct-download build): load a webpage locally in WebKit and
  snapshot it, behind a first-use privacy disclosure.

## [0.5.0] - 2026-06-12

### Added

- The **`vitrine` command-line renderer** now ships inside the app bundle, so a
  Homebrew install puts it on your PATH automatically.
- A **Settings ▸ General ▸ Command-line tool** action links the CLI for DMG
  installs.

## [0.4.0] - 2026-06-11

### Changed

- **Redesigned end to end:** the editor, Settings, Welcome, and the menu-bar panel
  now share one design language, in light and dark.
- The editor preview floats on an ambient-light stage and always scales to fit the
  window.
- Settings became a sidebar window with a pinned live preview and chip pickers for
  themes, fonts, and backgrounds.

### Added

- The menu-bar panel shows recent captures with thumbnails — reopen one, or copy
  its image again, in a click.
- The Welcome tour renders a real sample card you can restyle before your first
  capture.

## [0.3.0] - 2026-06-10

### Added

- New and restored editor windows size themselves to fit the screen, so nothing
  opens half off a smaller display.
- The Welcome tour and version-aware What's New now greet you on regular launches,
  not only from the Help menu.

## [0.2.0] - 2026-06-10

### Added

- Pasted code is re-indented by structure, so snippets copied from deep nesting
  land clean.

### Changed

- The AppKit main menu is fully localized, matching the rest of the app in Spanish.
- Updated KeyboardShortcuts to 2.4 and Sparkle to 2.9.3.

### Security

- Pasted-HTML snapshots no longer load remote subresources, keeping every render
  fully local.

## [0.1.0] - 2026-06-08

### Added

- Turn copied code into a beautiful image from the menu bar with a global hotkey.
- A focused editor with curated themes, developer fonts, and adjustable padding,
  corner radius, window chrome, and line numbers.
- Destination and style presets, plus custom solid, gradient, and image
  backgrounds.
- Copy or save as PNG or PDF, with rich-text and data-URI copy options.
- Private by design: fully local rendering, with no account, no network, and no
  screen-recording or Accessibility permission.

[Unreleased]: https://github.com/johnny4young/vitrine/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/johnny4young/vitrine/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/johnny4young/vitrine/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/johnny4young/vitrine/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/johnny4young/vitrine/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/johnny4young/vitrine/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/johnny4young/vitrine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/johnny4young/vitrine/releases/tag/v0.1.0
