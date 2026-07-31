# Vitrine — Architecture

This document mirrors the shipping module layout in [`Vitrine/`](../Vitrine) and the
runtime boundaries enforced by the test suite.

## Experience: menu-bar status item + panel

The app lives behind an AppKit `NSStatusItem`. Clicking the icon opens an
application-defined `NSPopover` whose SwiftUI content provides the capture action,
recent captures, theme shortcuts, and explicit command rows:

```
📸  [menu-bar icon]
├── 📋 New capture from clipboard            ⌘⇧S
├── 🖼️  Render clipboard as…                 ▸
├── 🕘 Recent captures
├── 🎨 Theme shortcuts
├── ✏️  Open editor…
├── 🌐 New web snapshot…
├── 🪪 New social card…
├── ───────────────
├── ⚙️  Preferences…                          ⌘,
├── ℹ️  About
└── ⏻  Quit                                   ⌘Q
```

- **Primary action — "New capture from clipboard"** (quick mode): reads `NSPasteboard`,
  detects code vs URL, detects the language for code, renders code with **your saved
  settings**, and leaves the result on the clipboard (**auto-copy configurable**) or
  saves it — **without opening any UI**. When URL capture is enabled, URL input opens
  Web Snapshot prefilled with the URL; the direct-download build then renders it locally
  with `WKWebView` after the first-use privacy disclosure.
- **"Open editor…"** opens the window with live preview and controls (theme, padding,
  font, background) to tweak before exporting.
- **Recent rows** reopen or re-copy the latest captures; the history link opens the full
  gallery.
- **Theme chips** change the saved default theme without opening the editor.

**Technical decision:** production uses a minimal `VitrineMenuBarHelper` child process
as the painted `NSStatusItem` owner. Control Center can retain every item associated with
the main process in an unpainted state even while AppKit reports it visible; a fresh
process identity avoids that host state. The helper inherits the app sandbox, contains no
product model, and reads no clipboard, settings, recents, or rendered content. A click
sends only both process identifiers, a per-launch token, and the pointer location over a
distributed notification. The main process validates all of them and
`StatusItemController` anchors its existing model-backed SwiftUI popover at that point.

The helper watches the exact containing app process and exits with it. The main app
monitors the helper and relaunches it if needed, retaining a stable in-process
`NSStatusItem` only as a launch fallback and for UI automation. This keeps one source of
truth for every command and prevents a second menu implementation from drifting.
Fallback-item teardown does not own the shared panel lifecycle. The external positioning
window also remains visible while the main app is inactive because the initiating click
belongs to the helper process. Vitrine therefore owns popover dismissal and monitors
pointer events plus workspace activation explicitly: events from the main app and its
helper stay inside the same interaction surface, while another process closes the panel.
The panel remains open while idle, then follows native menu behavior after an outside
interaction, focus change, Escape key, icon toggle, or explicit command action. SwiftUI
handles the cancel command, backed by a local AppKit key monitor when no control owns
focus. All close paths converge on the popover delegate lifecycle so monitor and anchor
cleanup cannot drift between input mechanisms. The large editor remains a separate
AppKit-hosted window. The global hotkey triggers quick mode or the editor depending on
the user's preference.

`StatusItemController` is also the menu-bar composition boundary. It retains one
`AppEnvironment` and supplies that graph, plus the explicitly owned feedback presenter
and window-navigation operations, to `MenuBarContent`. Every quick-capture entry from the
panel resolves settings, recents, Brand Kit watermark eligibility, and recovery actions
from that same graph. Panel rows route through the injected navigation value; only its
live adapter reaches the reusable AppKit window owners. The global hotkey and
application-menu command enter the same capture operation with the app-wide environment.
This keeps the render, history write, and any later recovery render aligned without
making the UI lifecycle presenter part of the data-store graph. The feedback presenter
likewise receives HUD display and recovery navigation as operation values, so neither
coordinator needs to construct UI during tests.

## Clipboard integration

- **Input:** on trigger (hotkey or menu) it auto-reads
  `NSPasteboard.general.string(forType: .string)` → the code is already loaded, no
  manual paste.
- **Output:** `Copy` writes the `NSImage` PNG to `NSPasteboard` → paste straight into
  Notion, Slack, X, Keynote.
- **Language detection** on paste (heuristic + manual override via the picker).
- **Permission:** a clear `NSPasteboardUsageDescription`; content **never leaves the
  Mac** (no network by default).

## Color management

PNG export is **sRGB by default**, and the exporter tags every image deliberately
rather than trusting `ImageRenderer`'s default: each render is redrawn through a
Core Graphics context in the chosen ICC space, so the embedded profile travels
with the file. sRGB is the safe choice because browsers, Slack, X, Keynote, and
non–color-managed viewers all assume it, so a screenshot looks the same
everywhere; **Display P3** is offered only as an explicit advanced option in
*Settings → Output → Advanced* — it keeps the wider gamut of a P3 display, but a
viewer that ignores the embedded profile renders P3 values as if they were sRGB,
which oversaturates the image, so it is opt-in rather than the default. Both
profiles preserve a real alpha channel: a transparent background exports with
true transparency (its empty pixels stay fully clear, `(0,0,0,0)`) and is never
composited over an opaque matte, so the result drops cleanly onto any slide or
page background.

## Vector export

The supported scalable format is **PDF**, not SVG. This is a deliberate decision
from the  spike, not an omission.

**Finding — there is no faithful full-canvas SVG path.** SwiftUI, `ImageRenderer`,
and AppKit expose no API that emits the rendered code canvas as vector SVG. A code
snapshot's text is laid out and rasterized by the text system (per-glyph kerning,
ligatures, sub-pixel positioning, theme attributes), and `ImageRenderer` can hand
back only a `cgImage`, an `nsImage`, or a `CGContext` it draws into — which is how
`ExportManager.pdfData` produces a real, color-managed vector PDF. There is no
public path that re-emits that glyph layout as SVG `<text>`/`<path>` vectors. So:

- **PDF is the vector format** offered in the export menu (`ExportFormat.pdf`,
  `isVector == true`); PNG is the raster option. The picker labels this honestly
  (`ExportFormat.summary`).
- **No fake SVG is shipped.** Vitrine never writes a `.svg` that is merely a raster
  PNG wrapped in an `<image>` element — that would be a raster file with a vector
  extension. PDF preserves a transparent background (real alpha, no matte), the
  same guarantee as the PNG path.

**The one place SVG is honest — the deterministic simple-template subset.** The
backgrounds of the social-card / simple templates are pure geometry and
color with no text layout, so they *can* be emitted as native SVG primitives.
`VectorTemplateSVG.background(_:size:)` serializes exactly that subset:

| Background        | SVG output                                             |
| ----------------- | ------------------------------------------------------ |
| `.solid`          | a filled `<rect>`                                      |
| `.gradient`       | an `objectBoundingBox` `<linearGradient>`              |
| `.customGradient` | an `objectBoundingBox` `<linearGradient>` (user stops) |
| `.transparent`    | no background rect (genuinely transparent, no matte)   |
| `.image`          | unsupported → returns `nil` (never embeds a raster)    |

Serialization is byte-for-byte deterministic (colors quantized through `RGBAColor`,
fixed number formatting and attribute order), so the same template always produces
identical bytes. This serializer is intentionally **not** wired up as a general
export choice for the arbitrary code canvas; it exists for the template path only.

## Command-line renderer

`vitrine render input.swift --out image.png` renders code to an image from the
command line, for docs pipelines and automation. It is a separate **`VitrineCLI`**
target (product name `vitrine`); the GUI app is unchanged.

**Hosting strategy.** `ImageRenderer` and Highlightr require AppKit on the **main
actor**, so a plain SwiftPM executable that never starts AppKit cannot render. Two
options were evaluated: (a) bundle a headless helper the CLI drives over IPC, or (b)
make the CLI itself a minimal AppKit host. Vitrine uses (b):
`VitrineCLI/main.swift` brings up the shared `NSApplication`, sets the **accessory**
activation policy (no Dock icon, no app-switcher entry, no menu bar), renders
synchronously on the main actor, and exits — it never shows a window and never calls
`app.run()`, so there is no UI and no event loop to get stuck in. This approach has no
IPC surface and keeps the render in-process where it can reuse the app's exact pipeline.

**Pixel-identical output.** The CLI does not re-implement rendering. The `VitrineCLI`
target compiles the same `Vitrine/` source tree (models, `SnapshotCanvas`,
`ExportManager`, `HighlightManager`, …) and supplies its own `main.swift`, excluding
only the SwiftUI `@main` app (`VitrineApp.swift`) so there is a single entry point. The
thin CLI layer lives in `Vitrine/CLI/`. `CLIArguments` is the stable dependency-free
facade; `CLIArgumentParser` owns token consumption and mutable invocation state;
`CLIArgumentValidation` checks cross-option semantics and materializes `CLIOptions`;
and `CLIArgumentValues` handles catalog and range conversion. `CLIOptions` then builds
a `SnapshotConfig` with the **same** preset/theme precedence the GUI uses.
`CLIRenderer` is the stable operation facade, `CLIRenderResources` owns temporary
background and watermark preparation, `CLIBatchRenderer` owns folder discovery and
batch reporting, and `CLIOutputWriter` owns artifact preflight, shared encoding, and
sidecars. The output component still calls the unchanged `ExportManager`; none of these
boundaries introduces a second render implementation. Because the inputs and pipeline
are identical, a CLI render is byte-for-byte identical to the app's export for the same
options — a focused output-contract test asserts exactly that.

**Test boundaries.** `Tests/CLI/` mirrors the production responsibilities: focused
suites cover entitlement, version and catalog contracts, argument parsing and
validation, configuration, rendering, and output behavior. Batch argument contracts
and filesystem rendering have separate suites because one is pure option validation
while the other creates real artifacts. `CLITestSupport` centralizes repository paths,
isolated scratch directories, and generated image fixtures without hiding assertions or
renderer calls.

**Defaults** match the app: a bare `vitrine render input.swift --out image.png` uses
`SnapshotConfig()`'s defaults (One Dark, JetBrains Mono, aurora background) at the
app's default scale. `--quiet` suppresses the success summary without hiding errors,
and `--json` swaps human success text for structured `render`/`batch` summaries; the
two flags are mutually exclusive so scripts cannot request JSON and suppress it.
`--theme`, `--language`, `--preset`, `--scale`, `--format`
(`png`/`pdf`/`heic`/`avif`), `--profile` (`srgb`/`p3`), `--font <family>`,
`--font-ligatures`, `--no-font-ligatures`, `--transparent`, `--background <id>`,
`--background-color <hex>`, `--background-image <path>`, `--background-fit <fill|fit>`,
`--background-blur <0...40>`, `--background-dimming <0...1>`, style controls
(`--font-size`, `--padding`, `--corner-radius`, `--shadow-radius`, `--wrap-columns`,
`--line-numbers`, `--no-chrome`, `--shadow`, `--no-shadow`, `--highlight-lines <spec>`,
`--redact-lines <spec>`, `--redact-secrets`, `--focus-lines`, `--no-focus-lines`,
`--diff-bands`, `--no-diff-bands`), and the header controls (`--window-title`,
`--filename`, `--title`, `--caption`, `--language-badge`) override individual choices.
Line specs are strict 1-based line/range lists such as `3,7-9,12`, so automation fails
loud instead of silently dropping malformed fragments; `--redact-secrets` reuses the
same deterministic `SecretScanner` as the editor and merges detected rows with any
manual `--redact-lines` ranges. Redacted rows are replaced with `[redacted]` before
copyable sidecars are written. For single-file renders, known output extensions
(`.png`, `.pdf`, `.heic`, `.avif`) infer the export format when `--format` is omitted; if an
explicit `--format` is present, the extension must match so automation never receives
mislabeled bytes. For piped input, `--stdin-name <name>` supplies filename context for
extension-based language inference and default metadata while still reading the source
only from standard input.
`--git-diff <revision-range>` is a bounded local source for `render` and `multi-size`.
`GitDiffInputLoader` executes `/usr/bin/git` directly with a fixed argument vector,
disables pagers, external diff drivers, textconv, and color, and puts repeatable
`--git-path` values after Git's `--` separator. Standard output is drained while Git
runs, avoiding pipe backpressure and terminating the process on the first byte above
the shared 5 MB source cap. Explicit source/destination prefixes and context prevent
global Git presentation settings from changing captures. Empty output fails before
rendering. Literal pathspecs prevent scope expansion, terminal prompts are disabled,
and `GIT_NO_LAZY_FETCH=1` prevents partial clones from reaching a promisor remote. The
loaded source is tagged `.diff`, and diff bands default on unless the caller explicitly
disables them.
Local CLI background images are imported once into an invocation-scoped
`BackgroundImageStore`; `CLIRenderer` threads that isolated store independently from
the foreground-image store through `ExportManager`, then removes it after a single
render or the complete batch. Automation inputs therefore never enter Application
Support, while every output still uses the shared `SnapshotCanvas` image-background
path.
Fit, blur, and dimming map directly to `ImageBackground`; their parser ranges are the
model's own bounds, and they are rejected without `--background-image` so inert style
options cannot silently pass in automation.
`--no-overwrite` / `--no-clobber` is an opt-in artifact safety guard: single renders
fail before replacing an image or sidecar, while batch jobs skip existing targets and
can pair that with skipped reports or `--fail-on-skipped`. A preset reframes
presentation/output (size, padding, background) and never touches the source, exactly
as in the GUI. Unknown ids and out-of-range values are rejected up front with
a clear message so an automation pipeline fails loud.

**Copyable sidecars.** `--text-sidecar`, `--markdown-sidecar`, `--html-sidecar`, and
the bundle shortcut `--sidecars <text|markdown|html|all>` write accessible source next
to the rendered image when `--out` is present. Terminal captures use the resolved
visible text (ANSI escapes and OSC links stripped) so the sidecar matches the pixels.
Markdown and HTML sidecars escape user-controlled filenames, image names, and source in
their respective syntax contexts before producing README or web embed blocks. If
`--redact-lines` or `--redact-secrets` is present, every sidecar is built from
`SnapshotConfig.sidecarText`, so the neutral placeholder is the only copyable
representation of those rows.

**Batch recursion.** `vitrine batch <folder> --out <folder>` remains top-level by
default for backward compatibility. `--recursive` opts into a full nested walk and
mirrors each input file's relative path under the output folder, so
`docs/examples/A.swift` becomes `out/docs/examples/A.png` (plus sidecars, when
requested) instead of colliding with another `A.swift` elsewhere in the tree.
`--dry-run` runs the discovery and text-decoding pass without creating the output folder
or writing images/sidecars, so CI can preflight a batch before spending render time.
`--include-ext <list>` narrows a batch to known source extensions, while
`--exclude-ext <list>` removes generated or temporary extensions before loading, so
filtered files are neither rendered nor reported as skipped. `--fail-on-empty` turns an
empty discovery/preflight into a failing exit, while `--fail-on-skipped` keeps successful
renders but returns a failing exit when any unreadable or non-text file was skipped,
which lets CI/docs jobs catch accidental inputs without losing the valid output
artifacts. `--skipped-report <json>` writes a local JSON array of skipped
`{path, reason}` entries before that strict exit, using paths relative to the input
folder so the artifact stays machine-independent; dry runs only write this artifact when
it is explicitly requested. `--manifest <json>` is the positive companion artifact: it
writes the successfully rendered outputs (or `planned` outputs during `--dry-run`) with
relative input/output paths, requested sidecar paths, language ids, formats, and
rendered dimensions when available. Same-stem inputs that would collide (`Widget.swift`
and `Widget.ts` → `Widget.png`) are disambiguated only for that group by preserving the
input extension, so non-colliding legacy output names stay unchanged.

**Catalog discovery.** `vitrine list <themes|languages|presets|fonts|backgrounds|formats|profiles>
[--json]` prints the same local catalog ids the parser validates for `--theme`,
`--language`, `--preset`, `--font`, `--background`, `--format`, and `--profile`;
`vitrine list all --json` returns one keyed object with every catalog for setup scripts that want a single
metadata call. It runs before AppKit initialization and before the PRO render gate
because it reads only bundled metadata, so scripts can cheaply discover valid options
without touching user files or rendering images.

**Shell capture context.** `vitrine shell-init` emits opt-in `vgrab` and `vpane`
functions for zsh, bash, and fish without installing prompt hooks or background
processes. A normal `vgrab` resolves the local Git root (falling back to the current
directory), resolves the current attached branch when available, and sends a combined
project/branch label plus the shell-escaped command through the existing `--filename`
and `--title` metadata options. Context therefore stays outside the ANSI transcript and
works for both scrolling output and reconstructed full-screen frames. It never reads
repository status, and `--no-context` omits the header for minimal or sensitive captures.

**Version metadata.** `vitrine --version` / `vitrine -v` / `vitrine version [--json]`
prints the installed CLI version before AppKit initialization and before the PRO render
gate. The helper prefers runtime bundle metadata, falls back to the enclosing app
bundle when the CLI is launched from `Vitrine.app/Contents/MacOS`, and finally uses
project-version constants guarded by tests against `project.yml` for development tool
builds.

**Local only.** Rendering needs no network, screen recording, or Accessibility — it is
the same fully local pipeline the app uses. The tool is not a sandboxed `.app`, so it
has no entitlements; it reads only the input file you name and writes only the output
you name.

**Bundled resources / distribution.** A command-line tool has no `Contents/Resources`,
so the build stages the resources the renderer needs **next to the binary**:

- The **Highlightr** resource bundle (`Highlightr_Highlightr.bundle`) is placed beside
  the binary automatically by SwiftPM, and `Bundle.module` resolves it there — this is
  what lets the CLI highlight without the app bundle.
- The **bundled monospaced fonts** are staged into a `Fonts/` folder beside the binary
  by a build phase (the GUI gets these via `ATSApplicationFontsPath`, which a tool
  lacks). `CLIEnvironment` locates that folder and `CLIFontRegistration` registers the
  fonts with Core Text at launch, so the default JetBrains Mono render matches the app
  instead of falling back to the system font.

To distribute, ship the `vitrine` binary together with its adjacent `Fonts/` folder and
`Highlightr_Highlightr.bundle` (e.g. copy all three into a single directory on `PATH`,
or wrap them in a tarball). Build the binary with `make cli`; the staged folder and
bundle are written into the same `BUILT_PRODUCTS_DIR`. A code-signed, notarized release
artifact is future work (see RELEASING.md); the current target is local/CI use.

## Automation: Shortcuts, Services, and App Intents

Vitrine meets users in the macOS automation surfaces they already use. Two are
exposed, and both reuse the **exact same render pipeline** as the editor, quick
capture, and the CLI, so their output is identical and they inherit the app's privacy
and sandbox posture unchanged — rendering is fully local, needs no network, screen
recording, or Accessibility, and the actions write nothing to disk on their own.

**Composition boundary.** The Services provider retains the `AppEnvironment` supplied
when it is constructed, so its PRO gate and exported style resolve from the same graph.
App Intents are constructed by the system rather than by an app-owned controller; each
`perform()` adapter therefore binds once to `AppEnvironment.shared` and uses that graph
for entitlement checks, Brand Kit watermarking, saved language history, and editor
handoff. The pure render request remains store-free and receives its base style as a
value. Theme lookup is also an operation dependency rather than a hidden store read:
portable callers use the built-in catalog by default, while app-owned adapters pass the
custom-theme resolver from their retained environment. This preserves deterministic
tests and keeps process-global state out of the render core.

**Shared core.** Like the CLI's `CLIOptions`/`CLIRenderer`, the automation surfaces
share one pure value type and one render shell, both in `Vitrine/AppIntents/`:

- `SnapshotRenderRequest` is the pure, value-typed request (code + optional language,
  theme, preset, scale, format, transparency, starting from a `baseStyle`). Its
  `makeConfig()` builds a `SnapshotConfig` with the **same precedence** the GUI uses
  (base style → preset → theme → transparent override), accepts theme lookup explicitly,
  and never lets a preset touch the code. It is unit-tested off the render path.
- `SnapshotRenderService` is the thin `@MainActor` shell that turns a request into
  PNG/PDF data or an `NSImage` through the **unchanged** `ExportManager`, adding only
  request resolution and an empty-input guard. A unit test asserts its bytes equal a
  direct `ExportManager` render of the same config — the same byte-identity guarantee
  the CLI carries.

**App Intents.** `RenderCodeImageIntent` ("Render Code to Image") is the headline
Shortcuts action: it takes code text plus task-named parameters (Language, Theme,
Destination, Format, Transparent Background, Resolution) and returns the rendered
image as an `IntentFile` the next Shortcut step can save, share, or copy. The picker
parameters are `AppEnum`s (`SnapshotLanguageAppEnum`, `…ThemeAppEnum`, `…PresetAppEnum`,
`…FormatAppEnum`) that mirror the model catalogs one-to-one, with sentinel cases
(Automatic / Default / None) for "let the app decide"; tests assert the cases and their
display titles cannot drift from `Language`/`Theme`/`ExportPreset`. `OpenCodeInEditorIntent`
("Open Code in Editor") is the "hand it to me to finish" path — it loads a snippet into
the editor for manual styling. `VitrineShortcuts` (an `AppShortcutsProvider`) surfaces
both to Spotlight/Siri with natural phrases. Linking `AppIntents.framework` (in
`project.yml`) is what lets the build's `appintentsmetadataprocessor` extract the actions
so they appear in Shortcuts.

**Services menu.** `CodeImageService` provides "Render Code Image with Vitrine" for a
text selection in any app that vends one to Services. The runtime hands the selection
in on an `NSPasteboard`; the provider renders it (detecting the language the same way
quick capture does) and writes the resulting PNG back onto that pasteboard so the host
app's paste/drop receives the image. Two things make a Service work and must agree: the
`NSServices` array in `Info.plist` (menu title, `NSMessage` = `renderCodeImage`, send
type plain text, return type image) and the runtime registration in `AppDelegate` via
`ServiceRegistration` (`NSApp.servicesProvider` + advertised send/return types). The
Objective-C selector is pinned with `@objc(renderCodeImage:userData:error:)` so it
matches the shape AppKit invokes regardless of the Swift argument label.

**No new permissions.** The automation surfaces add no entitlement and no Info.plist
capability beyond the `NSServices` declaration — the App Sandbox stays on, there is
still no network entitlement, and the only file access remains user-selected (the
Shortcuts-managed `IntentFile` and the Services pasteboard are not app-disk writes).
The CLI is excluded from compiling these files: it is the scriptable path itself and
does not link `AppIntents`.

## User flow (happy path)

```
Copy code in any app  →  ⌘⇧S
    ↓
NSStatusItem (menu bar) → quick mode or editor
    ↓
CaptureEngine → NSPasteboard.general.string(forType: .string)
    ↓
RenderEngine (Product local rendering: code; web capture: URL/HTML/social cards)
  ├── SyntaxHighlighter (Highlightr — 160+ languages via Highlight.js)
  ├── Theme catalog (Theme + CustomThemeStore — selection persists via AppSettings)
  ├── BackgroundRenderer (gradients, solid, transparent)
  └── WindowChrome (decorative traffic lights, optional)
    ↓
Live preview with sliders (padding, radius, scale)  [editor mode only]
    ↓
ImageRenderer(content:) → PNG @ 2x/3x (perfect retina)
    ↓
ExportEngine
  ├── Copy to clipboard (NSPasteboard) ← primary action
  └── Save to file (NSSavePanel) / Share sheet
```

## First-run quick-start

A lightweight, **skippable** welcome window teaches the core loop the first time the
app runs and never again. It is gated by a single persisted flag,
`AppSettings.hasSeenWelcome`, stored in the app's defaults store; `AppDelegate`
calls `WelcomeWindowController.presentIfFirstRun()` after its launch hooks, so the
gate lives in one place.

- **Compact, one screen.** No multi-page tutorial: identity, the three-step loop
  ("copy code → press the hotkey → paste the image"), a sample snippet, a starting
  style picker, the hotkey recorder, a launch-at-login toggle, a local-only privacy
  badge, and a clear **Skip / Get Started**. Both buttons mark the flow seen and
  close; skipping unlocks nothing because every feature is already reachable from the
  menu bar.
- **Sample capture with no clipboard.** "Try a sample capture" renders a built-in
  snippet through `QuickCapture.renderText` — the same exporter path as a real
  capture — so a brand-new user sees the full loop work without copying anything
  first. "Open the editor" seeds the editor with the same sample when the document is
  empty.
- **Privacy taught up front.** The local-only / no-network / no-screen-recording
  promise is shown *before* the first capture, matching the posture documented above
  and in the README.
- **Reset returns to first run.** `AppSettings.resetToDefaults()` clears the flag, so
  "Reset All Settings" brings the quick-start back. UI tests drive it deterministically
  through launch hooks (`--show-welcome`, `--skip-onboarding`, `--reset-onboarding`)
  while isolating the flag via `VITRINE_USER_DEFAULTS_SUITE`.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Helper process — painted NSStatusItem                │
└────────────────────────┬─────────────────────────────┘
                         │ Authenticated click anchor
                         ▼
             ┌────────────────────────────┐
             │ Main app — SwiftUI popover │
             └─────────────┬──────────────┘
                           │ Commands or global hotkey (⌘⇧S)
             ┌─────────────┴──────────────┐
             ▼                            ▼
   ┌─────────────────┐          ┌──────────────────────────┐
   │ Quick mode      │          │ Editor (Window/NSPanel)  │
   │ clipboard → PNG │          │ Editor + Preview + ctrl  │
   │ no window       │          └────────────┬─────────────┘
   └────────┬────────┘                       │
            └──────────────┬─────────────────┘
                        ▼
            ┌──────────────────────────┐
            │  ExportManager            │
            │  ImageRenderer → PNG →    │
            │  NSPasteboard / NSSavePanel│
            └──────────────────────────┘
```

## Module / folder structure

```
Vitrine/
├── App/
│   ├── VitrineApp.swift       # @main + inert Settings scene
│   ├── AppDelegate.swift      # NSApp config, lifecycle, windows
│   ├── AppMenu.swift          # AppKit main-menu assembly and ownership
│   ├── VitrineCommands.swift  # command metadata and shortcut catalog
│   ├── AppCommandResponder.swift # process-scoped command actions
│   └── EditorCommandResponder.swift # key-editor command actions and validation
├── MenuBar/
│   ├── MenuBarAnchor.swift    # content-free helper/main message
│   ├── MenuBarHelperLauncher.swift # helper lifecycle + identity validation
│   ├── StatusItemController.swift # NSPopover + in-process fallback
│   ├── MenuBarContent.swift   # the popover panel (SwiftUI)
│   └── QuickCapture.swift     # no-UI quick mode: clipboard → PNG
├── Onboarding/
│   └── WelcomeView.swift      # first-run quick-start + window controller
├── Editor/
│   ├── EditorView.swift       # scene shell + window-level state
│   ├── EditorExportSheet.swift # one export/paywall presentation destination
│   ├── EditorView+Toolbar/Stage/Annotations/DragDrop.swift
│   │                         # focused editor regions and interactions
│   ├── CodeEditorView.swift   # NSViewRepresentable over NSTextView
│   ├── CodeFormatter.swift    # stable tidy/trim/dedent facade
│   ├── CodeFormatter+JSON.swift
│   ├── CodeFormatter+Markup.swift
│   ├── CodeFormatter+Reindent.swift
│   ├── CodeFormatter+SQL.swift # dependency-free language-family transforms
│   ├── CodeFormatter+LanguageStrategy.swift # Language → safe formatter route
│   ├── HighlightManager.swift # Highlightr wrapper
│   └── LanguageDetector.swift # detection by extension / heuristic
├── Canvas/
│   ├── SnapshotCanvas.swift   # the view that becomes the PNG
│   ├── WindowChrome.swift     # decorative traffic lights
│   └── BackgroundView.swift   # solid or gradient background
├── Export/
│   ├── ExportManager.swift    # stable render-and-encode facade
│   ├── ExportManager+Pasteboard.swift # source/image clipboard delivery
│   ├── ExportManager+File.swift # save-panel and file delivery
│   ├── ExportManager+Batch.swift # multi-size and carousel delivery
│   ├── ShareManager.swift     # NSSharingService
│   ├── MultiSizeExportView.swift # multi-size export sheet (PRO)
│   ├── RichPasteboard.swift   # RTF/HTML copyable-text flavors alongside the image
│   └── VectorTemplateSVG.swift # deterministic SVG for the simple-template subset
├── Terminal/                  # ANSI/VT terminal rendering (see docs/TERMINAL.md)
│   ├── ANSIParser.swift       # escape-sequence tokenizer
│   ├── TerminalGrid.swift     # VT screen model (CSI dispatch, scrollback, alt screen)
│   ├── ANSIPalette.swift      # 16/256-color + truecolor palettes
│   └── CharacterWidth.swift   # cell-width classification (wide/combining glyphs)
├── Settings/
│   ├── AppSettings.swift      # UserDefaults-backed settings store (injectable)
│   ├── SettingsWindow.swift / SettingsRootView.swift # custom preferences window
│   ├── General/Style/Output/Input/Library/AboutSettingsView.swift
│   │                         # pane-level settings surfaces
│   ├── BrandKitSettingsSection.swift / SettingsSharedControls.swift
│   ├── CustomThemeStore.swift # built-in + user theme catalog and persistence
│   ├── CustomThemeFileExchange.swift # user-initiated theme JSON panels
│   ├── PresetStore.swift      # reusable-style catalog and persistence
│   └── PresetFileExchange.swift # user-initiated JSON import/export panels
├── Models/
│   ├── Theme.swift
│   ├── StoredCustomTheme.swift # validated portable theme record
│   ├── CustomThemeDocument.swift # validated theme JSON exchange envelope
│   ├── Language.swift
│   ├── SnapshotConfig.swift
│   ├── ExportPreset.swift     # fixed destination sizing and presentation guidance
│   ├── StyleSnapshot.swift / StylePreset.swift
│   │                         # portable presentation state + reusable catalog entries
│   ├── StylePresetDocument.swift # validated JSON exchange envelope
│   └── GlobalShortcuts.swift  # KeyboardShortcuts.Name definitions
├── Feedback/
│   ├── Notifier.swift         # quick-capture outcome banners
│   └── DiagnosticsBundle.swift # privacy-safe "Export diagnostics…"
├── CLI/                       # `vitrine render` core, shared with VitrineCLI
│   ├── CLIArguments.swift     # stable dependency-free parser facade
│   ├── CLIArgumentParser.swift # command selection, tokens, and invocation state
│   ├── CLIArgumentValidation.swift # cross-option rules → immutable CLIOptions
│   ├── CLIArgumentValues.swift # catalog, range, color, and geometry conversion
│   ├── CLIError.swift / CLIUsage.swift # process errors and help contract
│   ├── CLICatalog.swift       # local theme/language/preset discovery for automation
│   ├── CLIOptions.swift       # parsed options → SnapshotConfig (app-matching defaults)
│   ├── CLIRenderer.swift      # stable render/multi-size/edit/batch operation facade
│   ├── CLIRenderResources.swift # invocation-scoped backgrounds and watermark logos
│   ├── CLIBatchRenderer.swift # folder discovery, output planning, manifests, reports
│   ├── CLIOutputWriter.swift  # ExportManager encoding, artifact preflight, sidecars
│   └── CLIFontRegistration.swift # register bundled fonts with Core Text at launch
├── AppIntents/                # Shortcuts/Siri actions, app-only
│   ├── SnapshotRenderRequest.swift   # pure request → SnapshotConfig (app precedence)
│   ├── SnapshotRenderService.swift   # @MainActor shell over unchanged ExportManager
│   ├── SnapshotIntentEnums.swift     # AppEnum pickers mirroring the model catalogs
│   ├── RenderCodeImageIntent.swift   # "Render Code to Image" → IntentFile
│   ├── OpenCodeInEditorIntent.swift  # "Open Code in Editor" → editor window
│   └── VitrineShortcuts.swift        # AppShortcutsProvider (phrases for Spotlight/Siri)
├── Services/                  # macOS Services menu action, app-only
│   ├── CodeImageService.swift # provider: selected text → rendered PNG on pasteboard
│   └── ServiceRegistration.swift # NSApp.servicesProvider + send/return types
├── Pro/                       # Vitrine PRO open-core gate — see docs/PRO.md
│   ├── Entitlements.swift / StoreKitProvider.swift / LicenseKey.swift
│   └── BrandKit.swift / ProGate.swift   # (CLI side: CLI/CLIEntitlement.swift)
├── WebRendering/              # URL/HTML capture via WKWebView, app-only
│   ├── URLRenderer.swift      # URL render facade, validation/error mapping
│   ├── URLSnapshotEngine.swift # bounded offscreen WKWebView rasterization
│   ├── URLLoadCoordinator.swift # navigation completion + redirect/host policy
│   ├── HTMLRenderer / CodeRenderer / WebSnapshotView
│   ├── WebSnapshot{WindowController,EditorView}.swift
│   ├── WebSnapshotConfig.swift       # viewport/wait/capture-mode value type
│   ├── WebURLValidation.swift        # http(s)-only + SSRF host blocklist (typed errors)
│   ├── NetworkCapability.swift       # network-entitlement gate for URL capture
│   └── ResponsiveBoardComposer.swift # multi-viewport board (deterministic)
├── SocialCards/               # social-card editor + renderer; Canvas/SocialCardCanvas
├── Rendering/                 # shared Renderer / RenderedAsset abstractions
├── DesignSystem/              # VitrineTokens + Token components (the redesign system)
├── State/                     # RecentsStore + pure window-state model
├── Recents/ · Updates/ · Help/ # recents gallery; SoftwareUpdater (Sparkle on DMG); Help/What's New
├── Support/
│   ├── AppDefaults.swift      # UserDefaults routing (real app vs isolated UI tests)
│   └── Log.swift              # os.Logger per subsystem + render signposts
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── Vitrine.entitlements

VitrineMenuBarHelper/          # sandbox-inheriting status-item helper target
├── main.swift                 # paint-only NSStatusItem owner
└── VitrineMenuBarHelper.entitlements

VitrineCLI/                    # the `vitrine` executable target
├── main.swift                 # minimal accessory NSApplication host → CLIRenderer
└── CLIEnvironment.swift       # locates the Fonts/ folder staged next to the binary
```

The editor owns batch-export presentation at the toolbar root rather than at an
individual density-specific control. Expanded buttons and the compact actions menu
select one `EditorExportSheet` destination, and one `.sheet(item:)` host presents the
multi-size exporter, carousel exporter, or the corresponding paywall. This keeps
window-level presentation mutually exclusive while the toolbar adapts to available
width.

The live editor keeps high-frequency document text in
`AppSettings.documentCode`, separately observable from the normalized
`renderConfiguration` that contains every other `SnapshotConfig` input.
`AppSettings.config` remains the complete, atomic facade used by export, session,
preset, and command paths: its getter merges both values and its setter splits them.
This boundary lets `PreviewCodeSynchronizer` debounce only typing while presentation
changes remain immediate. The preview receives the staged configuration through an
equatable `SnapshotCanvas`, so parent view updates with the same render inputs do not
re-run synchronous highlighting.

This coalescing intentionally uses `SnapshotConfig` value equality rather than a
second render fingerprint or shared hash cache. The existing highlight and export
caches already make a default cached export approximately 1–2 ms in the performance
suite, while hashing the full document would add linear work to the typing path.
Introduce another fingerprint only if a measured workload demonstrates a remaining
cache-key bottleneck.

### Build boundaries

`make build-boundaries` measures architectural build costs before a new module or
package boundary is introduced. It runs clean and no-op builds plus low-fan-out
Foundation and high-fan-out model changes in disposable DerivedData. It also compares
clean focused-test builds and test-runner startup between the app target and a temporary
hostless package built from the Foundation-only terminal parser. Both test paths compile
and execute the same tracked Swift Testing suite, and the command rejects results when
their executed-test counts differ. Exact package downloads are resolved once into a
shared cache so clean samples measure compilation rather than network variance.

The command defaults to seven samples and writes every sample, min/median/max, median
absolute deviation, hardware/toolchain provenance, and complete relative-path logs beneath
ignored `build/` paths. A p95 is emitted only with at least twenty samples. The command
restores every sampled source timestamp and never changes tracked content. Run baseline
and candidate measurements on the same idle machine and power source; alternate their
order when thermal or background-load drift is plausible. Set `BUILD_BOUNDARY_BASELINE`
to the earlier JSON report to include per-metric median deltas in the new report;
comparison fails when the machine, memory, power source, macOS, architecture, or Xcode
version differs. Only a report whose provenance says `baseline_eligible: true` came from
a clean exact commit with at least the default seven samples; ineligible baselines are
rejected unless the caller explicitly overrides that guard. The two incremental scenarios
alternate order between samples to reduce systematic warming bias. A hostless micro-test
result alone does not justify shipping another module: the candidate must also improve
the real app build, preserve or improve incremental compilation, avoid duplicate model
definitions, and pass the full unit, performance, golden, and UI gates.

## Libraries

| Library             | How to add                                                   | For                                                   |
| ------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| `Highlightr`        | SPM ([raspu/Highlightr](https://github.com/raspu/Highlightr)) | Syntax highlighting (Highlight.js — 160+ languages)   |
| `KeyboardShortcuts` | SPM ([sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) | Configurable global hotkey                             |
| `Sparkle`           | Vendored framework (`scripts/fetch-sparkle.sh`, checksum-pinned) | Auto-update on the direct-download build only (stripped from the App Store binary) |
| AppKit / SwiftUI / `ImageRenderer` / `CryptoKit` / `WebKit` | Built-in | `NSStatusItem`, View→PNG, Ed25519 license verify, URL/HTML capture |

> The Settings window is a custom SwiftUI shell (`Settings/SettingsRootView.swift`), not
> the `sindresorhus/Settings` package, which has been removed.
> The Vitrine PRO monetization subsystem is documented in **`docs/PRO.md`**.

**Why Highlightr and not swift-syntax:** swift-syntax only covers Swift; Highlightr
supports 160+ languages via Highlight.js (battle-tested). Enough for v0.1; later it
could be complemented with Tree-sitter.

## Data model

`Models/SnapshotConfig.swift` is the render contract — everything that defines the
final image (code, language, theme, typography, padding, background, chrome, line
numbers, annotations, watermark, redacted ranges, wrap columns, terminal geometry,
foreground image, …). The struct has outgrown any snippet that could live here
without rotting; **the source file and the doc comment on each field are
normative.** The supporting enums below are stable and small enough to quote:

Custom themes follow the same separation as reusable style presets. `Theme` remains the
render-facing value, `StoredCustomTheme` provides its portable record, and
`CustomThemeDocument` validates the JSON exchange envelope. `CustomThemeStore` owns the
built-in and user catalog plus user-defaults persistence without importing AppKit;
`CustomThemeFileExchange` alone presents user-initiated open and save panels. Tests under
`Tests/Themes/` mirror color parsing, palette validation, document, catalog, persistence,
rendering, and editor-draft responsibilities. Portable style application accepts a theme
resolver: standalone consumers retain the built-in fallback, while `AppSettings` supplies
the live custom-theme catalog.

Destination and reusable-style presets are deliberately separate. `ExportPreset`
describes fixed output surfaces such as OpenGraph and presentation guidance for those
surfaces. `StyleSnapshot` captures portable presentation state, `StylePreset` adds
identity and the built-in catalog, and `StylePresetDocument` validates the JSON exchange
envelope. `PresetStore` owns the in-memory/user-defaults catalog without importing AppKit;
`PresetFileExchange` alone presents user-initiated open and save panels. Tests under
`Tests/Presets/` mirror these boundaries so persistence, schema validation, catalog
immutability, and settings application can evolve independently.

`SettingsResetCoordinator` keeps global reset side effects out of the SwiftUI view.
`AppSettings` remains the single owner that removes persisted values and resets its own
state; the coordinator then reloads the independent preset, theme, and Brand Kit stores
so their observable catalogs match the cleared defaults immediately.

`AppDelegate` is the process-lifecycle composition boundary. It retains one
`AppEnvironment` and one capture-feedback presenter, so URL handoffs, entitlement
updates, onboarding gates, and global-hotkey captures cannot resolve data from different
store graphs. Explicit development and UI-automation arguments are handled by
`AppLaunchArgumentHandler`, which receives the same environment; this keeps fixture
seeding and window-capture support out of the production lifecycle delegate. AppKit
window controllers and the stateless highlighter cache remain UI lifecycle leaf
singletons as documented above.

`AppMenu` owns the AppKit command surface and retains one app-command responder plus one
editor-command responder for its full lifetime. Both are created from the
`AppEnvironment` and capture-feedback presenter supplied by `AppDelegate`; rebuilding a
menu after SwiftUI displaces it therefore reuses the same command graph. Quick capture,
theme resolution, fallback editor settings, and the What's New command cannot escape to
independent global stores. Window controllers remain process-wide UI lifecycle leaves,
while toolbar formatting constructs a responder over the current editor's own settings.
The command metadata remains in `VitrineCommands.swift`; app-scoped actions and
key-editor actions live in separate responder files so menu descriptions, process
navigation, and document mutation can evolve without sharing one implementation unit.

`SettingsRootView` accepts one `AppEnvironment` and passes that graph through every pane.
Settings views do not default back to global stores: the Style preview, Brand Kit
controls, reusable-style catalog, entitlement gates, and reset path therefore observe
the same instances in production, previews, and isolated tests. Live entitlement
providers likewise refresh their owning `Entitlements` instance rather than escaping
back to the shared graph.

`EditorWindowController` is the equivalent composition boundary for editor windows. It
passes one `AppEnvironment` and one transient-feedback operation to each `EditorSession`
and `EditorView`. A session still owns volatile document/style settings — primary windows
adopt the current working document, while additional windows seed only the default style
— but those settings are constructed with the same Brand Kit and entitlement instances
the view observes. Toolbar, stage, and session actions present outcomes through the
injected operation rather than discovering the shared HUD. The application-menu editor
responder receives that same operation from its retained capture-feedback presenter.
Reusable styles, custom-theme resolution, watermark previews, feature gates, upgrade
sheets, and feedback therefore cannot fall back to a different process-global graph.
Promoting a window's style also targets the environment that created that window.

`SocialCardWindowController` and `WebSnapshotWindowController` apply the same boundary to
the app's singleton auxiliary editors. Each controller retains the `AppEnvironment` that
created it and supplies that graph to its SwiftUI root. Social Card resolves the working
card, custom-theme catalog, Brand Kit action, and entitlement gate from those instances;
Web Snapshot resolves capture consent, viewport preferences, and export settings from
the same app settings. The Web Snapshot controller also supplies transient feedback and
app-owned presentation operations: capture and export outcomes never discover the HUD,
while authenticated-session and share-sheet routing stay behind a closure-backed adapter.
The windows remain reusable and app-global, but isolated tests no longer create roots
that silently observe or mutate process-global stores or construct presentation windows.

`RecentsGalleryWindowController` owns the equivalent boundary for capture history. Its
SwiftUI root receives the retained `AppEnvironment`, an editor-navigation operation, and
a transient-feedback operation. Gallery filtering and mutation therefore observe the
controller's Recents store and settings, while editor handoff and copy outcomes remain
testable without discovering app-owned windows or the HUD. Window ownership lives in a
separate source file so the gallery view stays a store-and-action surface rather than a
second composition root.

```swift
enum BackgroundStyle { case solid(Color); case gradient(GradientPreset); case transparent }

enum GradientPreset: String, CaseIterable {
    // `aurora` is the signature default; see docs/DESIGN-SYSTEM.md.
    case aurora = "Aurora", ocean = "Ocean", sunset = "Sunset",
         forest = "Forest", night = "Night", carbon = "Carbon"
}

struct Theme: Identifiable, Hashable {
    let id: String, displayName: String, hlJsTheme: String
    let appearance: Appearance      // .dark / .light — metadata only
    static let oneDark = Theme(id: "one-dark", displayName: "One Dark",
                               hlJsTheme: "atom-one-dark", appearance: .dark)
    // 13 built-ins, listed alphabetically by display name (Models/Theme.swift):
    // Dracula, GitHub, GitHub Dark, Gruvbox, Monokai, Night Owl, Nord, One Dark,
    // One Light, Solarized, Solarized Light, Tokyo Night, Xcode Dark.
    static let builtIns: [Theme] = [.dracula, .github, .githubDark, /* … */]
}
```

## UI/UX decisions

- **Native components:** SwiftUI/AppKit Picker, Slider, Toggle — they look native because they are.
- **Preview first:** the canvas takes ~60% of the editor. **WYSIWYG:** what you see is exactly what you export.
- **Dark mode by default:** One Dark as the initial theme.
- **Lightweight onboarding only:** first launch can teach the hotkey, local-only privacy
  posture, and a sample capture, but it must stay skippable and compact. Empty state:
  "Paste or type code…".
- **Perceived speed:** highlight with a debounce of ≤100ms; `Copy` < 300ms.
