# Vitrine — Architecture

This document mirrors the shipping module layout in [`Vitrine/`](../Vitrine) and the
runtime boundaries enforced by the test suite.

## Product and distribution boundaries

Vitrine has one open-core product contract, not separate demo and paid render engines.
There is **no expiring trial**: the indefinitely usable free core is the evaluation
surface, while PRO gates only additive output and automation at UI/CLI/system edges.
The render core never reads entitlement state, and the app never manufactures a temporary
PRO entitlement or a trial clock. This removes an entire expiry/offline/recovery state
machine and keeps free and PRO pixels on the same deterministic path.

Homebrew and the signed, notarized DMG are the canonical distribution channels. They
share the direct-download build, Sparkle updater, offline signed-license provider, and
embedded CLI; Homebrew additionally places the CLI on `PATH`. The optional App Store
build is a secondary GUI-only variant selected at build boundaries: it removes Sparkle,
network-backed features, and the CLI, and resolves PRO through StoreKit. Channel-specific
capabilities are compiled and entitlement-gated explicitly rather than discovered at
runtime.

The public binary floor is macOS 15 Sequoia. Required runtime qualification covers both
Sequoia and macOS 26 Tahoe, while the direct-download artifact remains universal
(`arm64` + `x86_64`). A separate scheduled Xcode 27 preview lane compiles and unit-tests
the same source on its macOS 26 host; it is an early toolchain warning, not a claim of
macOS 27 runtime support. A future runtime becomes supported only after its runner is GA
and the complete build, UI, visual, performance, and clean-Mac gates are promoted to the
required matrix.

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
The helper remains a raw executable in `Contents/MacOS`, but Xcode embeds its generated
Info.plist in the Mach-O `__TEXT,__info_plist` section. That gives the sandbox initializer
the stable `com.johnny4young.vitrine.menubar-helper` identity Tahoe requires before
Swift reaches `main`, without turning the paint-only child into a login item or a second
application bundle.

Before spawning it, the launcher reads both code signatures through Security.framework
and requires the same non-empty team identifier. Developer ID, App Store, and properly
signed development builds satisfy that inheritance boundary. Ad-hoc source builds do
not; they keep the in-process status item instead of repeatedly launching a child that
Tahoe would terminate in `libsecinit` before `main`.

The helper watches the exact containing app process and exits with it. The main app
monitors the helper and relaunches it if needed, retaining a stable in-process
`NSStatusItem` only as a launch fallback and for UI automation. This keeps one source of
truth for every command and prevents a second menu implementation from drifting.
Argument parsing, exact PID/bundle owner matching, watchdog decisions, and historical
status-item visibility repair live in a pure contract shared by both targets. Unit tests
therefore exercise the helper's lifecycle policy without launching a second process or
painting an item into the developer's real menu bar.
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
the user's preference. Development and UI-automation runs can open that same popover at
a validated current-screen anchor through an explicit launch hook. Panel behavior tests
and screenshot tours therefore exercise the production content and dismissal lifecycle
without depending on whether the status item has usable accessibility geometry.

`StatusItemController` is also the menu-bar composition boundary. It retains one
`AppEnvironment` and supplies that graph, plus the explicitly owned feedback presenter
and window-navigation operations, to `MenuBarContent`. Every quick-capture entry from the
panel resolves settings, recents, Brand Kit watermark eligibility, and recovery actions
from that same graph. Panel rows route through the injected navigation value; only its
live adapter reaches the reusable AppKit window owners or terminates the process. Image
and source-copy outcomes enter the lifecycle-owned feedback presenter, which updates the
transient HUD and the status retained by the open panel together. The global hotkey and
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

## Raster resource budgets and failure contract

Every raster render/export path preflights `RenderBudget` after layout resolves the logical
canvas but before `ImageRenderer`, Core Graphics, or WebKit creates the potentially large
bitmap. Small fixed-size sampling/thumbnail operations derive from an already bounded image
and retain their own hard caps. The value-only render policy accounts for logical
dimensions, render scale, total pixels, and estimated simultaneously live buffers using
overflow-safe integer arithmetic. Preview and export use separate ceilings: preview
remains responsive, while export permits larger intentional output without granting an
unbounded allocation.
Full-page Web Snapshot height is clamped from the same axis, pixel, and estimated-byte
constraints before `WKWebView.takeSnapshot` is called, and the returned image is checked
again before board composition.

`RenderBudgetError` is the shared typed failure boundary: `tooLarge`, `allocationFailed`,
`encodingFailed`, and `cancelled`. The app, CLI, App Intents, batch exporters, social cards,
comparison boards, Web responsive boards, pasteboard, and file writers preserve those
categories instead of turning them into a blank image, partial success, or process-level
allocation failure.
User-facing adapters own concise recovery copy; the core error never exposes a file path or
platform allocation detail.

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

## Syntax-highlighting memory and responsiveness

`HighlightManager` owns one long-lived Highlight.js context, but its derived output is
disposable. Five deterministic `CostLimitedLRUCache` instances cover the native attributed
string, SwiftUI bridge, row split, terminal bridge, and terminal row split. Each cache is
bounded by both count and a conservative four-MiB estimated-cost budget (at most 20 MiB across
all five estimates); a theme key contains
the built-in stylesheet name or the complete custom palette rather than a mutable display id.
This prevents stale custom-theme colors and replaces the former FIFO behavior, where a hot
document could be evicted by a one-off inspector/render combination.

The accepted source-file ceiling and the interactive-highlighting ceiling are deliberately
different contracts. A source can still be loaded up to the shared five-MiB safety limit, but:

- syntax sources up to 32 KiB may enter the derived caches;
- 32–128 KiB sources are highlighted without caching and use a 250 ms trailing editor debounce;
- sources over 128 KiB remain editable and renderable as theme-legible plain text, with an
  explicit editor notice instead of a silent visual change.

The ordinary editor and preview debounces remain 100 ms and 90 ms respectively. Entering the
large-document fallback clears existing token colors once; later keystrokes inherit plain typing
attributes rather than recoloring the whole document. Terminal captures keep their separate
parser/emulator semantics and bypass caches above 32 KiB; their deeper large-stream policy belongs
to the terminal reliability boundary rather than pretending ANSI input is syntax highlighting.

## Bounded static image pipeline

`BackgroundImageStore` applies one contract to backgrounds, foreground screenshots, Brand Kit
logos, drag/drop, remote downloads, and CLI image inputs. It reads at most 25 MiB, then
`ImageDecodePolicy` inspects ImageIO source and per-frame status plus dimensions with caching
disabled. Import validation therefore does not allocate every frame merely to prove that metadata
is plausible; truncated containers fail the completeness check, frame tables are capped at 256,
and cumulative source geometry is capped at 64 megapixels.

Vitrine produces static artifacts, so an animated source has an explicit **first-frame** contract.
The resolver never uses `NSImage(contentsOf:)`, which can retain a full-resolution animated
representation. It asks ImageIO for one orientation-corrected thumbnail and constrains that decode
to the interactive `RenderBudget` (16 megapixels and an 8,192-pixel axis ceiling) before creating
the AppKit image. The process cache is still cost-bounded at 256 MiB, but its cost now reflects the
actual downsampled surface rather than unbounded source metadata.

Picker, drag/drop, remote, Brand Kit, and image-memory-journey imports run bounded read,
validation, hashing, atomic persistence, and first decode on Swift 6.2's explicit concurrent
executor. The main actor publishes the reference and creates/caches the final `NSImage` only after
that work completes. Existing stored references retain a synchronous bounded fallback so launch,
CLI, and migration behavior remains compatible.

Remote image transport does not iterate `URLSession.AsyncBytes` one byte at a time. A dedicated
ephemeral `URLSessionDataDelegate` feeds the chunks delivered by Foundation into a
subtraction-safe collector. A known oversized `Content-Length` is rejected before body delivery;
otherwise the first chunk that would cross 25 MiB is rejected without being appended and the data
task is cancelled before the typed `tooLarge` error resumes its caller. The same one-shot state
machine makes caller cancellation authoritative while retaining the public-to-private redirect
block.

## Terminal rendering: two engines

Terminal capture is not "syntax highlighting with an ANSI palette". Two structurally
different programs write to a terminal, and rendering either one the other's way
produces a wrong image, so `Vitrine/Terminal/` ships **two renderers behind one
entry point**. The user-facing guide is [TERMINAL.md](TERMINAL.md); this section is
the design rationale behind it.

`ANSIRenderer.styledRuns(_:columns:)` is the router. Both engines return `[ANSIRun]`,
so everything downstream — image layout, themes, the copyable sidecars — is identical
whether the source was `git log` or `htop`.

**The routing decision.** `TerminalScreen.usesScreenAddressing(_:)` inspects the byte
stream for evidence that the program is addressing screen *cells* rather than
appending *lines*:

| Sequence                      | Meaning                       | Why it is a trigger                        |
| ----------------------------- | ----------------------------- | ------------------------------------------ |
| `ESC[?1049h` / `?47h` / `?1047h` | enter the alternate screen | the unambiguous signature of a TUI         |
| `ESC[…J` (`ED`)               | erase display                 | only a full-screen redraw erases the screen |
| `ESC[…d` (`VPA`)              | absolute row                  | positioning implies a fixed screen          |
| `ESC[…r` (`DECSTBM`)          | scroll region                 | only a screen model has regions             |
| `ESC[…H` / `f` (`CUP`) past home | absolute cell               | home alone is ambiguous, so it is excluded  |

Plain colored output carries only `SGR`, so `git`, `ls`, and a test run never trip
this and stay in line mode.

**Line mode is the correct answer, not the fallback.** Scrolling output has no final
frame — the transcript *is* the artifact, and a reader expects every line of it. So
line mode parses the whole stream verbatim after `ANSIRenderer.normalize(_:)` cleans
the control bytes a pseudo-terminal leaves behind (`\r` redraws, `\b` backspaces,
stray `^D`/BEL from `script`), keeping tab, newline, and ESC for the parser.

**Grid mode deliberately skips `normalize`.** That function collapses exactly the
`\r`/`\b` sequences the emulator needs to interpret as cursor motion, and strips
escapes it depends on. Feeding normalized text to the cell buffer would destroy the
input it exists to replay. `TerminalScreen` instead replays the stream into a
two-dimensional buffer of `TerminalCell` and reports the final frame — including
scroll regions, scroll up/down, and `ICH`/`DCH`/`ECH`. It also snapshots the alternate
frame before an in-alt full clear, because `nvim` and `lazygit` erase the screen
*before* leaving the alt buffer on exit, which would otherwise capture a blank screen.

**The progress-bar idiom is handled in line mode, on purpose.** Spinners (`ora`, npm,
cargo) emit `EL`/`CHA` but never address the screen, so routing them to the grid would
be wrong. `ANSIRenderer.lineEdit(finalByte:params:)` maps them where `\r` is already
handled:

| Sequence           | Mapped? | Reason                                                        |
| ------------------ | ------- | ------------------------------------------------------------- |
| `EL 1`, `EL 2`     | discard the line | everything since `lineStart` is exactly start-to-cursor, so this is exact, not an approximation |
| `CHA` (empty or 1) | discard the line | returning to column 1 is what `\r` means                |
| `EL 0`             | left to the parser | erases *forward* from a cursor already at the end — a no-op |
| `CHA n>1`          | left to the parser | without a real cursor the options are to pad or truncate, and truncating deletes text a program aligned |

**Cell width is a model, not a font question.** `CharacterWidth.displayWidth(_:)`
classifies each scalar as two columns (CJK, emoji), one, or zero (combining marks), so
a frame dense with wide glyphs does not drift column by column. The caveat is
downstream and honest: the image is laid out as flowed monospaced text, so *pixel*
alignment of a wide glyph still depends on the code font's advance. The cell model is
exact; the rendering is as good as the font.

**Width is inferred unless pinned.** `inferColumns`/`inferRows` derive a replay size
wide enough that no addressed cell or printed line wraps early. The error is
deliberately asymmetric: the grid trims trailing blanks, so over-estimating is
harmless, while under-estimating wraps a TUI's content wrong — hence a floor of 80
columns. `vgrab -w <cols>` and `vitrine render --terminal-width` pin the width
instead, so wraps match what was on screen.

**Verifying a change.** `ANSIRenderer.plainText(_:columns:)` returns the reconstructed
visible text and backs the `--text-sidecar` output, so a terminal-rendering change can
be asserted as text rather than compared as pixels — diff the sidecar, not the PNG.

## Comparison-board composition

The reusable comparison core accepts two to four finished `RenderedAsset` values and
produces one color-normalized `RenderedAsset`. `ComparisonBoard` is deliberately
path-free: each item contains rendered pixels plus a short user-visible label and
optional detail, never a source URL, security bookmark, or identifier into Recents.
Composing or exporting a board therefore cannot trigger an implicit file read.

`ComparisonBoardComposer` resolves row and column counts before rendering and gives
every item an equal, aspect-fit image area. Automatic layout keeps two or three items
in one row and uses a two-by-two grid for four; explicit horizontal, vertical, and grid
layouts are deterministic alternatives. The finished image goes through the same color
normalization and PNG/PDF encoders as every other capture. This generic core remains
separate from `ResponsiveBoardComposer`, whose variable-width cards and viewport labels
are specialized for web snapshots.

The app workflow keeps that core behind two explicit state boundaries. Recents enters an
ephemeral selection mode backed by `ComparisonBoardSelection`, which owns ordered capture
identifiers only until the user cancels or creates a board.
`ComparisonBoardWindowController` then renders the selected captures once and hands
finished pixels with fresh draft-local identities to a `ComparisonBoardDraft`; later
caption, layout, and reorder edits never reread Recents or a source document. That one
render uses and retains the active output scale, preventing later Settings changes from
enlarging one-times source pixels. The controller injects app settings, feedback, and
sharing into `ComparisonBoardEditorView`, so the SwiftUI editor does not discover
process-global stores, HUDs, windows, or share services. `ComparisonBoardPreview` keeps
rendering, validation, and renderer-failure states distinct while retaining the last good
image during a debounced refresh. File encoding belongs to `ComparisonBoardExporter`,
which renders once through the draft's captured scale and sends the resulting pixels
through the shared raster/PDF encoders. Closing the window releases the entire draft and
preview, and no board state enters `UserDefaults` or restoration.

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

**Capability boundary.** The shell-generated `vgrab` helper dispatches one deliberately
constrained `terminal-capture` command. It always resolves terminal language, requires
clipboard copy or editor handoff, and its parser allowlist accepts only capture width and
filename/title context. That basic path is free. General `render`, `multi-size`,
`batch`, and `vpane` remain PRO and verify the signed offline token at the executable
boundary before file work. `CLIOptions.Command.requiresPro` uses an exhaustive switch
so every future command must make an explicit product decision; a new general flag
remains unavailable to the free command until its allowlist is deliberately changed.

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

**Portable workspace recipes.** `WorkspaceRecipeDocument` is a versioned JSON envelope
over the existing `StyleSnapshot` model. It can add portable header metadata, output
defaults, and one embedded custom theme, but it cannot encode source, workspace, or
output paths. The CLI accepts a recipe only through an explicit `--recipe <path>`;
`CLIRecipeLoader` requires a regular file, caps it at 1 MB, and never searches parent
folders, repositories, or app storage. `CLIRecipeCommand` provides stateless
`recipe validate` and `recipe show` inspection without creating a machine-local registry.
Configuration resolution stays deterministic: built-in defaults, destination sizing,
recipe values, an explicit built-in style preset, then explicit CLI flags. Recipe
inspection runs before AppKit initialization and the PRO render gate. Machine-local
workspace-to-recipe associations stay at an app-owned boundary and are never serialized
back into the portable document. `WorkspaceRecipeStore`, constructed by
`AppEnvironment`, persists only read-only security-scoped folder and recipe bookmarks
plus leaf display names. It resolves the most-specific associated ancestor only when a
source file is explicitly dropped, then `AppSettings.applyWorkspaceRecipe` preserves the
document and applies every app-representable style, metadata, destination, and output
value. A custom recipe canvas remains CLI-only and is reported as such by Settings.

**Session-only living snapshots.** `LivingSnapshotSession` belongs to one
`EditorSession`, not to `AppEnvironment` or a persistent store. The **Live file** picker
is the only entry point: it selects one source file, applies the same bounded text loader
used by drag and drop, and retains that file's security scope only while the editor
window remains open. Filesystem access sits behind an async, `Sendable` `FileClient`.
Swift 6.2 `@concurrent` entry points move metadata lookup and the bounded descriptor read
off the main actor; decoding policy stays centralized, and editor state is applied only
on the main actor. A 650 ms task compares file size, modification date, resource
identifier, and filesystem file/volume numbers; including inode identity detects editors
that save by atomically replacing the file instead of mutating its original inode.
Content is read only after the stamp changes.

The session records the last text it applied. When the editor still equals that baseline,
a saved version replaces it and clears content-bound marks through the normal
`LoadedFile.apply` policy. When the user has edited locally, the disk version becomes a
visible pending change and requires **Reload** or **Keep**; it never overwrites the
draft in the background. A transient read failure does not advance the observed stamp,
so the same atomic save remains retryable. Replacing the document through another input,
loading an image, closing the window, restoring a draft, or stopping the watcher releases
the scope and cancels polling, picker reads, and content reads. Each replacement also
invalidates a monotonic generation. That second guard rejects a late filesystem result
even when cancellation cannot force an in-progress POSIX read to return immediately.
Only one content read is session-owned at a time. The URL, watcher, tasks, and security
scope are excluded from window restoration and app defaults; ordinary file drops remain
one-time imports.

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
`--filename`, `--title`, `--caption`, `--language-badge`, `--no-language-badge`) and an
explicit `--recipe <path>` override individual choices.
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

Raster availability is capability-driven rather than version-switched:
`ExportFormat.availableCases` caches `CGImageDestinationCopyTypeIdentifiers()` once and
interactive pickers expose only writers the active ImageIO stack actually provides.
That keeps PNG/PDF/HEIC available on Sequoia while adding AVIF on Tahoe and newer.
Persisted or imported AVIF settings fall back to PNG on a Mac without the writer; the
CLI grammar remains stable across OS versions and returns an encoding failure rather
than ever writing mislabeled bytes.
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
metadata call. It runs before AppKit initialization and before the capability gate
because it reads only bundled metadata, so scripts can cheaply discover valid options
without touching user files or rendering images.

**Shell capture context.** `vitrine shell-init` emits opt-in `vgrab` and `vpane`
functions for zsh, bash, and fish without installing prompt hooks or background
processes. `vgrab` uses the constrained free `terminal-capture` command; `vpane` uses
the general PRO renderer. A normal `vgrab` resolves the local Git root (falling back to
the current directory), resolves the current attached branch when available, and sends
a combined project/branch label plus the shell-escaped command through the existing `--filename`
and `--title` metadata options. Context therefore stays outside the ANSI transcript and
works for both scrolling output and reconstructed full-screen frames. It never reads
repository status, and `--no-context` omits the header for minimal or sensitive captures.

**Version metadata.** `vitrine --version` / `vitrine -v` / `vitrine version [--json]`
prints the installed CLI version before AppKit initialization and before the capability
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

For direct distribution, the app build embeds the CLI as
`Vitrine.app/Contents/MacOS/vitrine-cli`; the signed, notarized DMG signs it as nested
code, and the Homebrew cask exposes that exact embedded executable on `PATH` as
`vitrine`. `make cli` remains the standalone local build lane and stages its adjacent
resources in the same `BUILT_PRODUCTS_DIR`.

**Release trust boundary.** A stable annotated tag can build only a private signed,
notarized candidate: verification, packaging, digest/appcast/SBOM generation, attestation,
and fresh-runner artifact QA happen without modifying public distribution. Manual
promotion names the successful candidate run and exact SHA-256 and requires recorded
clean-Mac QA; it verifies the tag commit and candidate provenance, downloads the same
artifact, and runs QA again before immutable publication. The public DMG then passes a
third download QA before Homebrew, the production appcast, or the website moves. See
[`docs/RELEASING.md`](RELEASING.md) for the operator procedure.

Release identity remains one reviewable source contract: `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` live in `project.yml`, while the newest changelog section,
bundled What's New entry, source cask template, App Store metadata, CLI fallback, and
website release highlights must agree before a candidate is tagged. Public website,
Homebrew-tap, appcast, and GitHub Release state intentionally remain unchanged until the
separately authorized promotion verifies the exact candidate bytes.

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
RenderBudget preflight → ImageRenderer(content:) → PNG @ 2x/3x
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
  menu bar. The root has a 700-point ideal width but can shrink to 480 points, and the
  controller clamps it using AppKit's own visible-frame coordinate space so hosted,
  split-screen, and compact-display layouts keep their trailing actions reachable.
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

`WelcomeWindowController` supplies `WelcomeNavigation` to the SwiftUI root, keeping the
sample-editor action at the AppKit composition boundary. `WhatsNewWindowController` does
the same with `WhatsNewNavigation`: opening Help still stamps the displayed release as
seen and dismisses the notes, but the view no longer discovers the process-wide Help
controller. Both roots remain directly composable in isolated tests without constructing
another application window.

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
            │  RenderBudget → PNG →     │
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
│   ├── WelcomeView.swift      # first-run quick-start + window controller
│   └── WelcomeNavigation.swift # injected sample-editor route
├── Editor/
│   ├── EditorView.swift       # scene shell + window-level state
│   ├── EditorExportSheet.swift # one export/paywall presentation destination
│   ├── EditorView+Toolbar/Stage/Annotations/DragDrop.swift
│   │                         # focused editor regions and interactions
│   ├── CodeEditorView.swift   # NSViewRepresentable over NSTextView
│   ├── LivingSnapshotSession.swift # volatile explicit-file refresh + conflict policy
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
│   ├── BatchExportPresentation.swift # directory UI + completion policy
│   ├── ShareManager.swift     # NSSharingService
│   ├── MultiSizeExportView.swift # multi-size export sheet (PRO)
│   ├── CarouselExportView.swift # multi-slide export sheet
│   ├── ComparisonBoard.swift # path-free validated 2–4 item value
│   ├── ComparisonBoardComposer.swift # equal-card deterministic composition
│   ├── ComparisonBoardExporter.swift # captured-scale raster/PDF encoding
│   ├── RichPasteboard.swift   # RTF/HTML copyable-text flavors alongside the image
│   └── VectorTemplateSVG.swift # deterministic SVG for the simple-template subset
├── Comparison/
│   ├── ComparisonBoardSelection.swift # ordered ephemeral Recents selection
│   ├── ComparisonBoardDraft.swift # rendered pixels + editable session captions
│   ├── ComparisonBoardPreview.swift # debounced preview phase and failure state
│   ├── ComparisonBoardEditorView.swift # preview, layout, captions, export controls
│   └── ComparisonBoardPresentation.swift # injected share operation
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
│   ├── WorkspaceRecipe.swift # path-free style/metadata/output exchange envelope
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
│   ├── CLIRecipeLoader.swift  # explicit bounded recipe file loading
│   ├── CLIRecipeCommand.swift # stateless recipe validate/show inspection
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
│   ├── PrivateNetworkBlockRules.swift # all-resource literal-private content rules
│   ├── HTMLRenderer / WebSnapshotView
│   ├── WebSnapshot{WindowController,EditorView}.swift
│   ├── WebSnapshotConfig.swift       # viewport/wait/capture-mode value type
│   ├── WebURLValidation.swift        # http(s)-only + SSRF host blocklist (typed errors)
│   ├── NetworkCapability.swift       # network-entitlement gate for URL capture
│   └── ResponsiveBoardComposer.swift # multi-viewport board (deterministic)
├── SocialCards/               # social-card editor + renderer; Canvas/SocialCardCanvas
├── Rendering/                 # shared Renderer / RenderedAsset abstractions
│   └── RenderBudget.swift     # overflow-safe raster policy + typed failures
├── DesignSystem/              # VitrineTokens + Token components (the redesign system)
├── State/                     # RecentsStore + pure window-state model
├── Recents/ · Updates/ · Help/ # recents selection/navigation; updates; Help/What's New
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

All app-owned targets inherit `SWIFT_TREAT_WARNINGS_AS_ERRORS`. Compiler diagnostics from
a new Swift or macOS SDK are compatibility signals that must be resolved deliberately;
they cannot accumulate silently behind otherwise-green CI results.

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
`AppEnvironment`, capture-feedback presenter, and editor-presentation operations supplied
by `AppDelegate`; rebuilding a menu after SwiftUI displaces it therefore reuses the same
command graph. Quick capture, theme resolution, fallback editor settings, image sharing,
and the What's New command cannot escape to independent global stores or presenters.
Window controllers remain process-wide UI lifecycle leaves, while toolbar formatting
constructs a responder over the current editor's own settings and presentation routes.
The command metadata remains in `VitrineCommands.swift`; app-scoped actions and key-editor
actions live in separate responder files so menu descriptions, process navigation, and
document mutation can evolve without sharing one implementation unit.

`SettingsRootView` accepts one `AppEnvironment` and passes that graph through every pane.
Settings views do not default back to global stores: the Style preview, Brand Kit
controls, reusable-style catalog, entitlement gates, and reset path therefore observe
the same instances in production, previews, and isolated tests. Live entitlement
providers likewise refresh their owning `Entitlements` instance rather than escaping
back to the shared graph.

`EditorWindowController` is the equivalent composition boundary for editor windows. It
passes one `AppEnvironment`, one transient-feedback operation, and one closure-backed
presentation value to each `EditorSession` and `EditorView`. A session owns ephemeral,
process-local document/style settings — primary windows adopt the current working document, while
additional windows seed only the default style — but those settings are constructed with
the same Brand Kit and entitlement instances the view observes. Toolbar, stage, and
session actions present outcomes through injected operations rather than discovering the
shared HUD, pinned-window controller, share-sheet manager, or key window. A successful
close-after-copy targets only the concrete window captured by the editor root; a failed
clipboard write leaves it open for recovery. Multi-size and carousel sheets receive the
session's feedback operation plus a narrow `BatchExportPresentation` value for directory
selection and Finder reveal. Their pure completion policy requires every expected output
before dismissing, so an inconsistent writer result cannot silently claim success. The
application-menu editor responder receives the feedback and presentation operations from
the lifecycle-owned menu. Reusable styles, custom-theme resolution, watermark previews,
feature gates, upgrade sheets, feedback, pinning, sharing, and batch export presentation
therefore cannot fall back to a different process-global graph. Promoting a window's style
also targets the environment that created that window.

`SocialCardWindowController` and `WebSnapshotWindowController` apply the same boundary to
the app's singleton auxiliary editors. Each controller retains the `AppEnvironment` that
created it and supplies that graph to its SwiftUI root. Social Card resolves the working
card, custom-theme catalog, Brand Kit action, and entitlement gate from those instances;
Web Snapshot resolves capture consent, viewport preferences, and export settings from
the same app settings. Both controllers also supply transient feedback and app-owned
presentation operations. Social Card rendering remains independent from the share sheet,
while Web Snapshot keeps authenticated-session and sharing routes behind a closure-backed
adapter. Web Snapshot export-all reuses `BatchExportPresentation` for directory selection
and Finder reveal, plus `BatchExportCompletion` for exact output accounting; partial writes
remain visible as failures and never trigger a success reveal. The windows remain reusable
and app-global, but isolated tests no longer create roots that silently observe or mutate
process-global stores or construct presentation windows.

`RecentsGalleryWindowController` owns the equivalent boundary for capture history. Its
SwiftUI root receives the retained `AppEnvironment`, an editor-navigation operation, and
a transient-feedback operation. The navigation value also routes an explicit ordered
capture selection to `ComparisonBoardWindowController`; neither the gallery nor the board
editor reaches that lifecycle owner directly. Gallery filtering and mutation therefore
observe the controller's Recents store and settings, while editor handoff and copy outcomes
remain testable without discovering app-owned windows or the HUD. Window ownership lives
in a separate source file so the gallery view stays a store-and-action surface rather than
a second composition root. The gallery keeps search and all library actions in an adaptive
in-content bar: `ViewThatFits` uses one row at desktop widths and two rows on compact
windows. This avoids AppKit toolbar overflow dropping actions from the accessibility tree.

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
