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

### Changed

- **Shared terminal captures now explain themselves.** `vgrab` adds a compact header
  with the local project, current Git branch when available, and executed command;
  repository status stays private, while `--no-context` keeps output-only and
  sensitive-command captures clean.
- **CLI maintenance is now split along explicit boundaries.** Argument tokenization,
  cross-option validation, value conversion, help, and error contracts live in focused
  files, with parsing, validation, configuration, rendering, and output tests organized
  into matching suites.
- **App Store dry-run archives no longer treat app resources as CLI resources.** The
  command-line target excludes the app-only resource tree, and the sandboxed embed phase
  can follow Xcode's archived tool-product symlink without weakening script sandboxing.
- **Release tooling is reproducible and auditable.** CI installs the checksum-verified
  XcodeGen release, watches pinned external tools and artifact digests for upstream
  changes, validates App Store archives through Xcode instead of deprecated delivery
  tooling, and publishes an SPDX dependency inventory with every GitHub release.
- **Repository contributions now have an explicit lifecycle.** The public support and
  conduct policies, ownership rules, issue forms, squash-only merge policy, automatic
  merged-branch cleanup, and required CI checks make contribution and maintenance
  expectations discoverable and consistent.
- **Published releases are immutable and originate from annotated stable SemVer tags.**
  The release gate rejects lightweight or malformed tags before packaging starts, so a
  published version keeps durable metadata and cannot be rewritten in place.

## [0.23.0] - 2026-07-20

### Added

- **Faster, more precise annotation editing.** Selected marks can be duplicated,
  moved one point at a time with the arrow keys (ten with Shift), and sent to the
  front or back of the regular mark layer. Annotation undo/redo now uses a bounded,
  independently tested history.
- **Optional localhost webpage capture.** The direct-download build can capture a
  development server on this Mac after an explicit, default-off setting is enabled.
  The exception is limited to `localhost`, IPv4 `127/8`, IPv6 `::1`, and mapped
  loopback; `.local`, LAN, link-local, metadata, and other private addresses remain
  blocked for both initial requests and redirects.

## [0.22.0] - 2026-07-19

Faster editing, safer sharing, and a command palette that keeps every action close.

### Performance

- **The line-numbered / diff layout no longer re-splits the document every frame.** The
  gutter and diff bands slice the highlighted code into one line per row — a
  character-by-character walk that rebuilt on every preview frame. It's now cached on the
  same key as the highlight itself, so an unchanged snapshot reuses the split.
- **Custom themes are now cached like the built-ins.** A user-palette theme used to
  re-run its (slow) HTML-importer highlight on every preview frame — an inspector tweak
  or a keystroke re-tokenized the whole snippet each time. It's now cached on the palette
  itself, so a re-render that didn't change the code, palette, or font is a cache hit
  (measured: the custom-theme render's p95 dropped from ~88 ms to ~2 ms).
- **The live preview no longer re-highlights the whole document on every keystroke.**
  The editor's preview now renders a copy of the code that trails your typing by a short
  debounce, so a burst of keystrokes coalesces into one re-highlight once it settles
  instead of re-tokenizing the entire snippet on each character. Style edits (theme,
  padding, background) still update the preview instantly.

### Added

- **Share a snapshot as a link.** The copy menu gains *Copy share link*: a
  `vitrine://open` URL that reproduces the whole styled snapshot — code, theme,
  background, annotations, header — so a teammate opens your exact image with one click.
  Fully local (no server, no upload); the link carries no file references (an image
  background degrades to the signature gradient) and the code travels in clear text, so
  don't share a snapshot with a live secret. A snapshot too large to fit a link is
  reported rather than copied.
- **Redact secrets in a beautified image.** The one-click secret scan now works on
  dropped/pasted images, not just code: Settings-free, it runs on-device OCR (Vision),
  finds regions that look like API keys, tokens, or passwords, and covers them in the
  image itself — so the secret is gone from the exported bytes, correct whatever frame
  or padding is applied. Reuses the same detector as the code path, including its
  multi-line private-key handling.
- **Command palette (⌘K).** A fast, fuzzy-searched palette over the editor's actions —
  apply any theme, toggle line numbers / shadow / window chrome / wrap / ligatures, run
  Surprise Me, or copy/save/export — without hunting through the inspector. Type to
  filter (a subsequence match, so "clr" finds "Clear"), ↑/↓ to move, Return to run.

### Fixed

- **Latest editor and web-preview state now wins.** Cancelled or superseded asynchronous
  work can no longer publish a stale render after the user changes the input, mode, or
  configuration.
- **Keyboard and assistive-technology behavior is consistent across new controls.** The
  command palette, export actions, and related controls keep stable labels, identifiers,
  focus behavior, and complete English and Spanish localization metadata.
- **Shared snapshot links reject malformed or ambiguous URLs.** Parsing now accepts only
  the documented scheme and host, rejects credentials and unexpected components, and
  reports oversized or invalid payloads without partially applying them.

### Security

- **Remote and encoded inputs are bounded before expensive work.** Downloads,
  decompression, decoded images, snapshot-link payloads, and caches enforce explicit
  limits to prevent memory amplification and unbounded retention.
- **Remote destinations are validated throughout navigation.** URL capture and remote
  image import reject unsafe schemes, private/local destinations, and unsafe redirect
  results instead of validating only the initial string.

### Changed

- **Preview and rendering caches are bounded and keyed by the complete render inputs.**
  This keeps the performance gains deterministic without allowing caches to grow for the
  life of the process or reuse a result for a different configuration.

## [0.21.0] - 2026-07-16

From snapshot to post: split a long snippet into carousel slides, share to
X / LinkedIn / Bluesky in one paste, and annotate with a much bigger toolkit.

### Added

- **Carousel export (PRO).** Split a long snippet into numbered 4:5 slides
  (`carousel-01.png` …) for a LinkedIn/Instagram carousel: pick the lines per slide, the
  split balances so the last slide never trails with a line or two, and every slide
  renders through the standard pipeline with your style and brand mark (the font floors
  at 22 pt so slides stay legible at feed size).
- **Post to X / LinkedIn / Bluesky.** The share sheet gains compose targets: the image
  is staged on the clipboard and the network's compose page opens with a paste hint —
  one paste from posting, with nothing sent anywhere by Vitrine.
- **Measure tool.** A dimension callout for design handoffs: drag between two points
  and the mark draws a technical-style measurement — shaft, perpendicular end caps, and
  the span's length in pixels on a pill at the midpoint.
- **Pinned snapshot.** Pin the current render in a floating window that stays on top of
  every app (and follows you across Spaces), so the error or design you're working
  against stays visible while you code. One pin at a time; close it like any window.
- **Copy text from image.** A beautified screenshot can be turned back into copyable
  text: one click runs on-device OCR (Vision, nothing leaves the Mac) and puts the
  recognized text on the clipboard — the reverse of the copyable-text sidecar.
- **Suggested titles.** A wand next to the header-title field fills it from what the
  code declares — the filename chip, else the first declared identifier — shown only
  while it would change something.
- **QR link chip (PRO).** Give the Brand Kit a link (profile, repo, article) and the
  mark gains a scannable QR chip — generated fully on-device, integer-scaled so the
  modules stay crisp at any export scale.
- **Signature footer bar (PRO).** A new watermark placement: a full-width attribution
  strip along the bottom edge — logo and handle on the left, the QR chip on the
  right — instead of a floating corner badge.
- **Spotlight.** A new annotation tool dims everything except the regions you draw —
  the "look here" effect for walkthroughs. Multiple spotlights punch multiple holes in
  one scrim; arrows and callouts stay at full brightness above it.
- **Safe-area guides.** An editor-only overlay (Inspector ▸ Output ▸ Guides) draws the
  margin platforms may crop or cover over a fixed-size destination, plus a live
  "lines × widest column" chip — so you know the snippet fits before you post. Never
  part of the export.
- **Curved arrows.** A second arrow style (⌘0): a quadratic swoop with the chevron head
  kept tangent to the curve — the hand-drawn callout look — sharing the straight arrow's
  color and weight controls.
- **Emoji stickers.** A new annotation tool (⌘9) places reaction stickers — 👀 🔥 ✅ 🚀 and
  friends — from a curated picker; the size slider scales them, and they export exactly as
  previewed like every other mark.
- **Smart trim.** Format Code (⌥⌘F) and format-on-paste now also even out the whitespace
  around a snippet: stray blank lines above/below and per-line trailing spaces are dropped,
  so a paste lands balanced on the canvas. Markdown hard breaks (two trailing spaces) are
  preserved.
- **asciinema import.** Drop or open an asciinema recording (`.cast`, v2/v3) and Vitrine
  replays its output events into the terminal renderer — a recorded session becomes a styled
  terminal image with no conversion step.
- **`vpane` shell helper.** `vitrine shell-init` (zsh/bash/fish) now also defines
  `vpane [-e] [target-pane]`: copy a terminal image of a tmux pane's visible contents —
  colors included, nothing re-run — for what is already on screen (`vgrab` remains the
  run-and-capture path).
- **HEIC export.** A third output format alongside PNG and PDF — the same rendered,
  color-managed image in a far smaller container for docs sites and wikis. In the app's
  format picker and the CLI (`--format heic`).
- **Smarter save names.** The save panel now proposes a filename derived from the snapshot
  (the filename chip, else the first declared identifier in the code) instead of a fixed
  `vitrine.png`.
- **Markdown sidecar (CLI).** `vitrine render --markdown-sidecar` writes a `.md` next to the
  image: the image reference plus the source in a language-tagged fenced code block, ready to
  paste into a README or post so viewers can copy the code the image shows.

### Fixed

- Secret redaction now blurs every line of a PEM private key, not just its BEGIN banner.
- Terminal line mode: `ESC ( B` charset designations no longer leak a stray `B`; colon-form
  SGR parameters (`38:5:196`) no longer reset accumulated styles; a control byte inside a
  truncated CSI sequence no longer merges output lines.
- Files saved with a UTF-8 BOM no longer carry an invisible leading character into the editor.
- Malformed hex colors fall back to black instead of decoding a partial value; window
  restoration clamps the shadow radius like every other numeric field.
- Format-on-paste no longer re-indents the interior of multi-line string literals
  (backtick templates, Swift/Kotlin/Scala triple-quoted strings) or miscounts braces inside
  them.
- Importing a preset file (or loading the saved presets) with one corrupt entry now keeps
  the valid presets instead of discarding all of them.
- A wide (double-width) character rendered on a one-column terminal no longer writes past
  the right margin.
- Cancelling a webpage/HTML capture now stops promptly instead of waiting out the load
  timeout.

### Performance

- Image backgrounds and foreground ("beautify any image") snapshots are cached after the
  first decode, so dragging a slider or typing no longer re-reads the file from disk on
  every preview frame.
- A code-only edit (typing) no longer re-persists the whole style block to preferences.

## [0.20.0] - 2026-06-28

Turn *any* screenshot into a share-ready image — not just code.

### Added

- **Beautify any image.** Drop, paste, or quick-capture an arbitrary image (a screenshot, a
  design, a photo) and render it on the same backgrounds, padding, and shadow Vitrine gives
  your code. Wrap it in a frame — a macOS window, a browser window, or a **MacBook / iPhone**
  device mockup (drawn as crisp vectors, no bundled artwork). The editor's code column becomes
  an image panel (thumbnail + Remove), and the inspector swaps its code-only controls for a
  frame picker.
- **Auto frame chrome.** A frame's title/toolbar samples the image's top-edge color and tints
  itself to match, so it blends into the screenshot instead of clashing; the text color is
  chosen for contrast so it stays legible on any bar. Light and Dark remain manual overrides.

The plain image and the macOS window frame are free; the browser and device frames are part of
Vitrine PRO.

## [0.19.0] - 2026-06-28

A one-click safety net for the most embarrassing way to leak a credential: sharing a
screenshot with it still in frame.

- **Redact secrets in one click.** A new "Redact secrets" control in the editor's **Lines**
  section scans the capture for likely credentials — AWS / GitHub / Slack / Google / Stripe /
  OpenAI keys, JWTs, `-----BEGIN … PRIVATE KEY-----` blocks, and `name = long-value`
  assignments (`api_key`, `secret`, `token`, `password`, …) — and blurs the matching lines
  before you share. It errs toward catching: a false positive only blurs an extra line you
  can clear, while a miss would leak a key.
- **Leak-proof redaction, image *and* text.** Redacted lines are blurred in the rendered
  image, and the copyable text that travels with it — the clipboard text rider and the
  `--text-sidecar` / multi-size `.txt` — replaces those lines with a neutral `[redacted]`
  placeholder, so a secret the image hides can't slip out through the text either. For
  terminal captures the scan reads the ANSI-resolved screen, so the blur lands on the rows
  you actually see even after `\r`/`\b` redraws.

## [0.18.0] - 2026-06-28

A usability pass over the whole app from a 4-agent UX audit, shipped as one release.

### Added

- **Editable text annotations.** The Text annotation tool now opens a focused inline field
  on the canvas — type the note and press Return to commit; double-click an existing callout
  to edit it, and an empty one is dropped. (It previously dropped a fixed "Note" with no way
  to edit it.)
- **Keyboard shortcuts for annotation tools.** `⌘1`–`⌘8` select Select / Arrow / Line /
  Rectangle / Text / Highlighter / Blur / Counter; each tool's tooltip shows its shortcut.
- **Cancel a running web capture, with progress.** A multi-size URL capture now shows a
  Cancel button (and Escape) plus "Capturing N of M", so a long sequential batch is no
  longer a trap.
- **"Use my logged-in session" web capture.** An opt-in toggle captures URLs using your
  browser cookies/session; off by default, with a private per-render store otherwise.
- **Auto-capture a prefilled URL.** Quick-capturing a clipboard URL now starts the capture
  automatically instead of leaving you on a static form.

### Changed

- **Brand Kit is its own Settings pane** (was buried under Style), so the PRO feature is
  visible; the Settings panes also read clearer (Input → Export rename and a top-to-bottom
  pipeline order).
- **Scope clarity in the editor.** A note explains that the inspector styles *this capture*,
  while Settings ▸ Style sets the default that new captures start from.
- **Recents open consistently.** Opening a capture from the gallery now loads it into the
  editor window like the menu-bar Recents row, instead of overwriting your default style.
- **Quick-win polish.** Copy/Save confirm via the on-screen HUD, disabled buttons dim,
  inspector sliders show their value, the empty Recents state teaches the capture loop, and
  more controls carry VoiceOver labels.

### Fixed

- Robustness around the new capture-cancel and prefill flows: no dropped or stale
  auto-capture, and no capture re-entrancy races.

## [0.17.0] - 2026-06-27

### Added

- **Soft-wrap long code lines.** A new "Wrap long lines" control (editor inspector and the
  Settings Style pane) wraps a long line at a column width instead of producing an
  extremely wide image — the slider sets the width and the live preview reflows as you drag.
  Off by default, so existing snapshots render unchanged. In the line-number view the
  wrapped continuation hangs under the code column.

### Changed

- **Snappier live preview and recents.** The recents gallery now caches decoded thumbnails
  (no more re-reading PNGs from disk on every resize), and the editor's terminal and
  social-card previews cache their highlighted/bridged text, so editing stays smooth on
  large captures. Rendered output is byte-for-byte identical.
- **Modernized the state layer.** The settings/document stores moved to Swift's
  `@Observable` macro (finer-grained view updates, less boilerplate); no behavior change.
- **Release tooling.** The Homebrew-tap bump is now a reusable, validated script
  (`scripts/update-homebrew-tap.sh`) that refuses to publish a broken or unchecksummed cask.

## [0.16.1] - 2026-06-27

### Added

- **Responsive-board section on the landing page.** A new "One page, every screen" section
  shows how a single page is captured at several viewports and composed into one shareable
  responsive board, with a pure-CSS reconstruction of the real output (no image asset).

### Fixed

- **Responsive board captions no longer truncate.** A full-page capture is a tall, narrow
  card, so a one-line label like "Desktop (1440 × 900)" overran it and rendered as "Deskt…"
  in the exported image. The caption is now two lines — the preset name above its dimensions —
  with each card's column floored to a legible width, so every viewport reads in full.
- **Hardened remote background-image downloads.** Importing a background from a URL now
  streams through an ephemeral, size-bounded session that tears the transfer down the moment
  the cap is hit, and refuses private or redirected hosts before the request is followed.
- **Hardened PRO activation and CLI install.** License activation uses a private, bounded
  session instead of shared `URLSession` state, and the command-line tool's manual-symlink
  fallback POSIX-quotes its paths.

## [0.16.0] - 2026-06-26

### Changed

- **Web Snapshot & Social Card windows redesigned to match the Editor.** Both composers now
  use the shared inspector chrome (uppercase sections, labeled rows, collapsible disclosures
  for the advanced controls), branded empty states, a centered preview, and a title that sits
  in the traffic-light row — so they read as part of the same app as the editor instead of
  one-off panels. The multi-viewport viewport chips wrap into view in the narrow inspector.
- **Multi-viewport web capture is now discoverable.** "New Web Snapshot" and "New Social
  Card" appear in the menu-bar icon panel (not only the hidden top menu bar), and the README
  and landing page describe capturing several viewports at once into a shareable responsive
  board.

### Fixed

- **PRO purchase link.** The Lemon Squeezy store was renamed, so the checkout moved to a new
  subdomain; the in-app "Get Vitrine PRO" button and the landing page's buy button now point
  at the live store instead of a dead URL.

## [0.15.0] - 2026-06-26

### Added

- **Wide (double-width) characters in terminal captures.** The cell-buffer emulator now
  measures CJK ideographs and emoji as two columns and combining marks as zero, so a
  full-screen TUI dense with `你好` / `🚀` / accented text reconstructs without column
  drift — the value columns of an `htop` or a CJK dashboard line up where the program drew
  them.
- **`vitrine render --terminal-width <n>`** pins the reconstruction width (1–1000) instead
  of inferring it from the captured bytes, for pixel-exact wraps. `vgrab -w <cols>` now
  passes it through (alongside the `COLUMNS` it already exports for the captured program)
  and validates the value in zsh, bash, and fish.

### Changed

- **Faithful in-place line edits in terminal captures.** The emulator now honors character
  insert/delete/erase (`ICH` / `DCH` / `ECH`), so shells with inline autosuggestion and
  other programs that edit a line in place reconstruct correctly. Wide characters stay
  intact across edits, erases, and line clears — no orphaned half-glyphs.

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
- **Refreshed website.** The landing page adopts the "The Vitrine" visual direction
  (light-first, appearance toggle, interactive style bench).

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

[Unreleased]: https://github.com/johnny4young/vitrine/compare/v0.23.0...HEAD
[0.23.0]: https://github.com/johnny4young/vitrine/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/johnny4young/vitrine/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/johnny4young/vitrine/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/johnny4young/vitrine/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/johnny4young/vitrine/compare/v0.18.0...v0.19.0
[0.18.0]: https://github.com/johnny4young/vitrine/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/johnny4young/vitrine/compare/v0.16.1...v0.17.0
[0.16.1]: https://github.com/johnny4young/vitrine/compare/v0.16.0...v0.16.1
[0.16.0]: https://github.com/johnny4young/vitrine/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/johnny4young/vitrine/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/johnny4young/vitrine/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/johnny4young/vitrine/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/johnny4young/vitrine/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/johnny4young/vitrine/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/johnny4young/vitrine/compare/v0.9.0...v0.10.0
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
