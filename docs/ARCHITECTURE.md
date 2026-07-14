# Vitrine — Architecture

> In-repo copy of the technical design from the original spec. Mirrors the module
> layout in [`Vitrine/`](../Vitrine).

## Experience: menu bar + submenu

The app lives in `NSStatusItem` / `MenuBarExtra`. Clicking the icon opens a **native
menu with submenus** (not just a popover):

```
📸  [menu-bar icon]
├── 📋 New capture from clipboard            ⌘⇧S
├── ✏️  Open editor…
├── 🕘 Recents                               ▸
│        ├── func hello() { … }
│        ├── SELECT * FROM users …
│        └── (last 10 captures, reopenable)
├── 🎨 Theme                                 ▸
│        ├── One Dark                ✓
│        ├── GitHub
│        ├── Dracula
│        └── …
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
- **"Recents" submenu** lists the last captures; choosing one reopens it in the editor.
- **"Theme" submenu** changes the default theme with a check on the active one.

**Technical decision:** `MenuBarExtra` with `.menuBarExtraStyle(.menu)` for the native
submenu, plus a separate `Window` / `NSPanel` for the editor (large preview). The
global hotkey triggers quick mode or the editor depending on the user's preference.

## Clipboard integration

- **Input:** on trigger (hotkey or menu) it auto-reads
  `NSPasteboard.general.string(forType: .string)` → the code is already loaded, no
  manual paste.
- **Output:** `Copy` writes the `NSImage` PNG to `NSPasteboard` → paste straight into
  Notion, Slack, X, Keynote.
- **Language detection** on paste (heuristic + manual override via the picker).
- **Permission:** a clear `NSPasteboardUsageDescription`; content **never leaves the
  Mac** (no network by default).

## Color management (CS-024)

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

## Vector export (CS-023)

The supported scalable format is **PDF**, not SVG. This is a deliberate decision
from the CS-023 spike, not an omission.

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
backgrounds of the social-card / simple templates (CS-041) are pure geometry and
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

## Command-line renderer (CS-033)

`vitrine render input.swift --out image.png` renders code to an image from the
command line, for docs pipelines and automation. It is a separate **`VitrineCLI`**
target (product name `vitrine`); the GUI app is unchanged.

**Hosting strategy (the decision the CS-033 design note asked for).** `ImageRenderer`
and Highlightr require AppKit on the **main actor**, so a plain SwiftPM executable
that never starts AppKit cannot render. Two options were on the table: (a) bundle a
headless helper the CLI drives over IPC, or (b) make the CLI itself a minimal AppKit
host. We chose (b): `VitrineCLI/main.swift` brings up the shared `NSApplication`, sets
the **accessory** activation policy (no Dock icon, no app-switcher entry, no menu
bar), renders synchronously on the main actor, and exits — it never shows a window and
never calls `app.run()`, so there is no UI and no event loop to get stuck in. Option
(b) is simpler, has no IPC surface, and keeps the render in-process where it can reuse
the app's exact pipeline.

**Pixel-identical output.** The CLI does not re-implement rendering. The `VitrineCLI`
target compiles the same `Vitrine/` source tree (models, `SnapshotCanvas`,
`ExportManager`, `HighlightManager`, …) and supplies its own `main.swift`, excluding
only the SwiftUI `@main` app (`VitrineApp.swift`) so there is a single entry point. The
thin CLI layer lives in `Vitrine/CLI/`: `CLIArguments` (a dependency-free parser),
`CLIOptions` (which builds a `SnapshotConfig` with the **same** preset/theme precedence
the GUI uses), and `CLIRenderer` (which calls the unchanged `ExportManager`). Because
the inputs and the pipeline are identical, a CLI render is byte-for-byte identical to
the app's export for the same options — a unit test asserts exactly that.

**Defaults** match the app: a bare `vitrine render input.swift --out image.png` uses
`SnapshotConfig()`'s defaults (One Dark, JetBrains Mono, aurora background) at the
app's default scale. `--quiet` suppresses the success summary without hiding errors.
`--theme`, `--language`, `--preset`, `--scale`, `--format`
(`png`/`pdf`/`heic`), `--profile` (`srgb`/`p3`), `--transparent`, style controls
(`--font-size`, `--padding`, `--wrap-columns`, `--line-numbers`, `--no-chrome`,
`--no-shadow`), and the header controls (`--window-title`, `--filename`, `--title`,
`--caption`, `--language-badge`) override individual choices. For piped input,
`--stdin-name <name>` supplies filename context for extension-based language inference
and default metadata while still reading the source only from standard input.
`--no-overwrite` / `--no-clobber` is an opt-in artifact safety guard: single renders
fail before replacing an image or sidecar, while batch jobs skip existing targets and
can pair that with skipped reports or `--fail-on-skipped`. A preset reframes
presentation/output (size, padding, background) and never touches the source, exactly
as in the GUI (CS-020). Unknown ids and out-of-range values are rejected up front with
a clear message so an automation pipeline fails loud.

**Copyable sidecars.** `--text-sidecar`, `--markdown-sidecar`, `--html-sidecar`, and
the bundle shortcut `--sidecars <text|markdown|html|all>` write accessible source next
to the rendered image when `--out` is present. Terminal captures use the resolved
visible text (ANSI escapes and OSC links stripped) so the sidecar matches the pixels.
Markdown and HTML sidecars escape user-controlled filenames, image names, and source in
their respective syntax contexts before producing README or web embed blocks.

**Batch recursion.** `vitrine batch <folder> --out <folder>` remains top-level by
default for backward compatibility. `--recursive` opts into a full nested walk and
mirrors each input file's relative path under the output folder, so
`docs/examples/A.swift` becomes `out/docs/examples/A.png` (plus sidecars, when
requested) instead of colliding with another `A.swift` elsewhere in the tree.
`--dry-run` runs the discovery and text-decoding pass without creating the output folder
or writing images/sidecars, so CI can preflight a batch before spending render time.
`--include-ext <list>` narrows a batch to known source extensions, while
`--exclude-ext <list>` removes generated or temporary extensions before loading, so
filtered files are neither rendered nor reported as skipped. `--fail-on-skipped` keeps
successful renders but returns a failing exit when any unreadable or non-text file was
skipped, which lets CI/docs jobs catch accidental inputs without losing the valid output
artifacts. `--skipped-report <json>` writes a local JSON array of skipped
`{path, reason}` entries before that strict exit, using paths relative to the input
folder so the artifact stays machine-independent; dry runs only write this artifact when
it is explicitly requested. `--manifest <json>` is the positive companion artifact: it
writes the successfully rendered outputs (or `planned` outputs during `--dry-run`) with
relative input/output paths, language ids, formats, and rendered dimensions when
available. Same-stem inputs that would collide (`Widget.swift` and `Widget.ts` →
`Widget.png`) are disambiguated only for that group by preserving the input extension,
so non-colliding legacy output names stay unchanged.

**Catalog discovery.** `vitrine list <themes|languages|presets|formats|profiles>
[--json]` prints the same local catalog ids the parser validates for `--theme`,
`--language`, `--preset`, `--format`, and `--profile`. It runs before AppKit
initialization and before the PRO render gate because it reads only bundled metadata,
so scripts can cheaply discover valid options without touching user files or rendering
images.

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

## Automation: Shortcuts, Services, and App Intents (CS-034)

Vitrine meets users in the macOS automation surfaces they already use. Two are
exposed, and both reuse the **exact same render pipeline** as the editor, quick
capture, and the CLI, so their output is identical and they inherit the app's privacy
and sandbox posture unchanged — rendering is fully local, needs no network, screen
recording, or Accessibility, and the actions write nothing to disk on their own.

**Shared core.** Like the CLI's `CLIOptions`/`CLIRenderer`, the automation surfaces
share one pure value type and one render shell, both in `Vitrine/AppIntents/`:

- `SnapshotRenderRequest` is the pure, value-typed request (code + optional language,
  theme, preset, scale, format, transparency, starting from a `baseStyle`). Its
  `makeConfig()` builds a `SnapshotConfig` with the **same precedence** the GUI uses
  (base style → preset → theme → transparent override) and never lets a preset touch
  the code (CS-020). It is unit-tested off the render path.
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
RenderEngine (Product Phase 1: code; Product Phase 2: URL/HTML/social cards)
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

## First-run quick-start (CS-035)

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
│  NSStatusBar — menu-bar icon                          │
└────────────────────────┬─────────────────────────────┘
                         │ Click → menu with submenus  (or ⌘⇧S)
        ┌────────────────┴───────────────┐
        ▼                                 ▼
┌───────────────┐              ┌──────────────────────────┐
│ Quick mode    │              │ Editor (Window/NSPanel)  │
│ clipboard→PNG │              │  Editor + Preview + ctrl │
│ no UI         │              └────────────┬─────────────┘
└───────┬───────┘                           │
        └───────────────┬───────────────────┘
                        ▼
            ┌──────────────────────────┐
            │  ExportManager            │
            │  ImageRenderer → PNG →    │
            │  NSPasteboard / NSSavePanel│
            └──────────────────────────┘
```

## Module / folder structure

> The original spec used `Codeshot*` identifiers; they are renamed to `Vitrine*`
> here (e.g. `VitrineApp.swift`).

```
Vitrine/
├── App/
│   ├── VitrineApp.swift       # @main, MenuBarExtra scene graph
│   └── AppDelegate.swift      # NSApp config, lifecycle, windows
├── MenuBar/
│   ├── MenuBarContent.swift   # the menu + submenus (SwiftUI)
│   └── QuickCapture.swift     # no-UI quick mode: clipboard → PNG
├── Onboarding/
│   └── WelcomeView.swift      # first-run quick-start + window controller (CS-035)
├── Editor/
│   ├── EditorView.swift       # scene shell + window-level state
│   ├── EditorView+Toolbar/Stage/Annotations/DragDrop.swift
│   │                         # focused editor regions and interactions
│   ├── CodeEditorView.swift   # NSViewRepresentable over NSTextView
│   ├── HighlightManager.swift # Highlightr wrapper
│   └── LanguageDetector.swift # detection by extension / heuristic
├── Canvas/
│   ├── SnapshotCanvas.swift   # the view that becomes the PNG
│   ├── WindowChrome.swift     # decorative traffic lights
│   └── BackgroundView.swift   # solid or gradient background
├── Export/
│   ├── ExportManager.swift    # PNG, PDF, clipboard
│   ├── ShareManager.swift     # NSSharingService
│   ├── MultiSizeExportView.swift # multi-size export sheet (PRO, CS-093)
│   ├── RichPasteboard.swift   # RTF/HTML copyable-text flavors alongside the image
│   └── VectorTemplateSVG.swift # deterministic SVG for the simple-template subset (CS-023)
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
│   └── CustomThemeStore.swift # built-in + user theme catalog (CS-031)
├── Models/
│   ├── Theme.swift
│   ├── Language.swift
│   ├── SnapshotConfig.swift
│   └── GlobalShortcuts.swift  # KeyboardShortcuts.Name definitions
├── Feedback/
│   ├── Notifier.swift         # quick-capture outcome banners
│   └── DiagnosticsBundle.swift # privacy-safe "Export diagnostics…" (CS-048)
├── CLI/                       # `vitrine render` core, shared with VitrineCLI (CS-033)
│   ├── CLIArguments.swift     # dependency-free arg parser + CLIError/CLIUsage
│   ├── CLICatalog.swift       # local theme/language/preset discovery for automation
│   ├── CLIOptions.swift       # parsed options → SnapshotConfig (app-matching defaults)
│   ├── CLIRenderer.swift      # load input → ExportManager (unchanged) → write file
│   └── CLIFontRegistration.swift # register bundled fonts with Core Text at launch
├── AppIntents/                # Shortcuts/Siri actions, app-only (CS-034)
│   ├── SnapshotRenderRequest.swift   # pure request → SnapshotConfig (app precedence)
│   ├── SnapshotRenderService.swift   # @MainActor shell over unchanged ExportManager
│   ├── SnapshotIntentEnums.swift     # AppEnum pickers mirroring the model catalogs
│   ├── RenderCodeImageIntent.swift   # "Render Code to Image" → IntentFile
│   ├── OpenCodeInEditorIntent.swift  # "Open Code in Editor" → editor window
│   └── VitrineShortcuts.swift        # AppShortcutsProvider (phrases for Spotlight/Siri)
├── Services/                  # macOS Services menu action, app-only (CS-034)
│   ├── CodeImageService.swift # provider: selected text → rendered PNG on pasteboard
│   └── ServiceRegistration.swift # NSApp.servicesProvider + send/return types
├── Pro/                       # Vitrine PRO open-core gate (CS-088–094) — see docs/PRO.md
│   ├── Entitlements.swift / StoreKitProvider.swift / LicenseKey.swift
│   └── BrandKit.swift / ProGate.swift   # (CLI side: CLI/CLIEntitlement.swift)
├── WebRendering/              # URL/HTML capture via WKWebView, app-only (CS-043/044)
│   ├── URLRenderer / HTMLRenderer / CodeRenderer / WebSnapshotView
│   ├── WebSnapshot{WindowController,EditorView}.swift
│   ├── WebSnapshotConfig.swift       # viewport/wait/capture-mode value type
│   ├── WebURLValidation.swift        # http(s)-only + SSRF host blocklist (typed errors)
│   ├── NetworkCapability.swift       # network-entitlement gate for URL capture
│   └── ResponsiveBoardComposer.swift # multi-viewport board (deterministic)
├── SocialCards/               # social-card editor + renderer (CS-041); Canvas/SocialCardCanvas
├── Rendering/                 # shared Renderer / RenderedAsset abstractions
├── DesignSystem/              # VitrineTokens + Token components (the redesign system)
├── State/                     # RecentsStore + pure window-state model (CS-053)
├── Recents/ · Updates/ · Help/ # recents gallery; SoftwareUpdater (Sparkle on DMG); Help/What's New
├── Support/
│   ├── AppDefaults.swift      # UserDefaults routing (real app vs isolated UI tests)
│   └── Log.swift              # os.Logger per subsystem + render signposts (CS-048)
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── Vitrine.entitlements

VitrineCLI/                    # the `vitrine` executable target (CS-033)
├── main.swift                 # minimal accessory NSApplication host → CLIRenderer
└── CLIEnvironment.swift       # locates the Fonts/ folder staged next to the binary
```

## Libraries

| Library             | How to add                                                   | For                                                   |
| ------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| `Highlightr`        | SPM ([raspu/Highlightr](https://github.com/raspu/Highlightr)) | Syntax highlighting (Highlight.js — 160+ languages)   |
| `KeyboardShortcuts` | SPM ([sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) | Configurable global hotkey                             |
| `Sparkle`           | Vendored framework (`scripts/fetch-sparkle.sh`, checksum-pinned) | Auto-update on the direct-download build only (stripped from the App Store binary; CS-064) |
| AppKit / SwiftUI / `ImageRenderer` / `CryptoKit` / `WebKit` | Built-in | `NSStatusItem`, View→PNG, Ed25519 license verify (CS-090), URL/HTML capture (CS-043) |

> The Settings window is now a custom SwiftUI shell (`Settings/SettingsRootView.swift`, the
> design/handoff redesign), not the `sindresorhus/Settings` package, which has been removed.
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
