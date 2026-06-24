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

## [0.14.0] - 2026-06-24

### Added

- **Full-screen terminal apps (TUIs) → image.** Vitrine now captures `htop`, `btop`,
  `vim`, `lazygit`, `k9s`, `tig`, `less`, `man`, and other full-screen terminal apps —
  not just scrolling output. A cell-buffer terminal emulator reconstructs the program's
  *final screen* (cursor positioning, screen clears, scroll regions, and the alternate
  screen) with its colors intact, rendered in your theme; the surrounding shell prompt is
  left out. It kicks in **automatically** by content — `vgrab htop` captures the dashboard
  — while plain scrolling output (a `git log`, a test run) keeps rendering the full
  transcript line by line. See [docs/TERMINAL.md](docs/TERMINAL.md).

## [0.13.0] - 2026-06-23

### Removed

- **The `vlast` shell helper and its passive recorder.** `vlast` shared the *last*
  command you already ran, but recovering its color required an always-on recorder
  that re-exec'd your shell under `script` and sliced output with prompt hooks — real
  terminal overhead, and unreliable on macOS, where the system `script` block-buffers
  its recording so a short command's output often never reached `vlast`. `vgrab` is now
  the only shell helper: a plain function with no background recorder, no re-exec, and
  no effect on your terminal's performance. To capture a command you already ran, recall
  it (↑ or `!!`) and prepend `vgrab` — e.g. `vgrab !!`.

## [0.12.0] - 2026-06-23

### Added

- **One-click shell-integration setup.** Settings ▸ General ▸ Shell integration ▸
  **Set Up…** appends the `eval "$(vitrine shell-init …)"` load line to your startup
  file for you, so you no longer have to edit a dotfile by hand to get `vgrab` and
  `vlast`. It detects your shell from `$SHELL` (zsh, bash, or fish), is idempotent
  (re-running never duplicates the line), creates the file if it is missing, and falls
  back to a copyable `echo … >> <rcfile>` command if you decline the file grant.
- **`vgrab` and `vlast` in bash and fish.** The capture helpers and the passive
  "share your last command" recorder were zsh-only; they now work in bash (a `DEBUG`
  trap plus `PROMPT_COMMAND`) and fish (native `fish_preexec` / `fish_postexec`
  events) as well. fish loads the helpers with `vitrine shell-init fish | source`.
- **Nerd Font / Powerline glyphs in terminal images.** Terminal captures now render
  Powerline separators and prompt icons from tools like `starship` and `eza --icons`
  by cascading to a Nerd Font you already have installed — no bundled font is added,
  and when none is installed the render is byte-identical to before (no missing-glyph
  boxes appear in their place).
- **Open a capture in the editor (`--edit`).** `vgrab --edit`, `vlast --edit`, and
  `vitrine render … --edit` open the captured output in Vitrine's editor instead of
  copying it, so you can restyle, annotate, and choose an export before sharing. The
  handoff travels over a private named pasteboard and a `vitrine://edit` URL, never the
  general clipboard. (PRO.)
- **Terminal hyperlinks and a copyable-text sidecar.** OSC 8 hyperlinks in terminal
  output now render as styled links, and a new **Output ▸ Clipboard ▸ plain-text
  sidecar** toggle (and the `--text-sidecar` CLI flag) keeps the underlying text
  selectable: copying adds the plain text alongside the image, and each multi-size
  export writes a `.txt` next to its PNG.

## [0.11.0] - 2026-06-20

### Added

- **Terminal / ANSI renderer.** Paste raw shell or program output that carries ANSI
  escape codes — `git`, test runners, `ls --color`, build logs — and Vitrine renders
  it as a styled terminal image: the colors come from the escape codes (standard 16,
  256-color, and 24-bit truecolor) with bold / dim / italic / underline / strikethrough
  / inverse. It is a new **Terminal** language; pasting, quick-capturing, or dropping a
  file of colored output detects it automatically (the ANSI escapes override the file
  extension, and ANSI inside a single Markdown fence is unwrapped first so surrounding
  prose is dropped), and `vitrine render … --language terminal` works from the CLI.
  Progress bars and spinners show their final line — carriage-return and backspace
  redraws are resolved instead of concatenated.
- **Theme-aware terminal palettes.** The terminal card follows your Style theme: a light
  theme renders on a light card — the right look for light blogs, docs, and slides — and
  Dracula and Nord map to their own signature ANSI palettes.
- **Zero-friction terminal capture (`vitrine shell-init`).** Because programs drop
  color when their output isn't a real terminal, `eval "$(vitrine shell-init zsh)"`
  installs two helpers that force it for you: `vgrab <command>` runs a command under a
  pseudo-terminal and copies a terminal image of its colored output to the clipboard —
  passing through the command's own exit status, with `-w <cols>` to set the capture
  width — and `vlast` shares the **last** command you already ran — without re-running
  it — via a passive session recorder. New `vitrine render` flags `--copy` (image to the
  clipboard) and `--stdin` (read a pipe) back them. See [docs/TERMINAL.md](docs/TERMINAL.md).

## [0.10.0] - 2026-06-19

### Added

- **Brand Kit · Free placement.** Alongside the four corners, a new "Free" placement
  lets you drag the brand mark to any point on the image — directly in the editor
  preview and in the Settings ▸ Style preview.
- **Menu-bar tooltip + logo glyph.** The status-bar icon is the real Vitrine logo
  (a template image) and shows a "Vitrine" tooltip on hover.

### Changed

- **Controls follow the macOS system accent.** Selection, hover, links, chips, and
  segmented controls now track System Settings ▸ Appearance ▸ Accent color; on the
  default Multicolor they keep Vitrine's brand accent rather than the system blue.
  Accent-filled chips use the AppKit on-accent text color so they stay legible for
  every accent.
- **Annotations and highlighted lines reset on a new capture.** Loading new content
  — the Paste button, a select-all paste, a dropped file that replaces the document,
  or a quick capture — clears marks that were positioned over the old code; a
  mid-edit paste keeps them. Reusable style (theme, font, background, header) stays.
- **Native, legible Settings buttons.** The Library and the other Settings panes use
  explicit `.bordered` / `.borderedProminent` styles with a clear primary/secondary
  hierarchy instead of low-contrast accent-tinted titles.
- **Refreshed website.** The landing page adopts the "The Vitrine" design-system
  proposal (light-first, appearance toggle, interactive style bench).

### Fixed

- The single-instance guard no longer affects the unit-test host (it could abort a
  local `make test` when a developer instance was open).
- The free-placement watermark overlay is non-interactive, so it never blocks
  selection or editing of the content beneath it.
- The Style settings preview drops the editor's free-form annotations, so a stray
  blur or "Note" callout no longer muddies the style thumbnail.

## [0.9.0] - 2026-06-18

### Added

- **Buy Vitrine PRO.** The paywall on the direct-download build now leads with a
  "Get Vitrine PRO" button that opens the Lemon Squeezy checkout; the license-key
  field stays below to activate the key you receive by email. The landing page gains
  a Pricing section with the regular ($25) and early-bird ($19.99, through 2026)
  prices and the same checkout link.

## [0.8.1] - 2026-06-16

### Changed

- **Vitrine PRO direct-download activation is live.** The signed release build now embeds
  the license-signing key, so pasting a Lemon Squeezy license key in the paywall unlocks
  Brand Kit, multi-size export, and automation — verified offline on every later launch. No
  app-logic change from 0.8.0; the release pipeline now ships the key (the public key was
  already committed). A from-source or PR build still has no key and stays free.

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

[Unreleased]: https://github.com/johnny4young/vitrine/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/johnny4young/vitrine/compare/v0.8.1...v0.9.0
[0.8.1]: https://github.com/johnny4young/vitrine/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/johnny4young/vitrine/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/johnny4young/vitrine/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/johnny4young/vitrine/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/johnny4young/vitrine/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/johnny4young/vitrine/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/johnny4young/vitrine/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/johnny4young/vitrine/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/johnny4young/vitrine/releases/tag/v0.1.0
