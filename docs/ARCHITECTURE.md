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
  saves it — **without opening any UI**. URL input is detected and deferred until
  Product Phase 2, when it will render locally with `WKWebView`. This is the
  lowest-friction path without compromising the Phase 1 no-network promise.
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
  ├── ThemeManager (@AppStorage — theme persists across sessions)
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
├── Editor/
│   ├── CodeEditorView.swift   # NSViewRepresentable over NSTextView
│   ├── HighlightManager.swift # Highlightr wrapper
│   └── LanguageDetector.swift # detection by extension / heuristic
├── Canvas/
│   ├── SnapshotCanvas.swift   # the view that becomes the PNG
│   ├── WindowChrome.swift     # decorative traffic lights
│   └── BackgroundView.swift   # solid or gradient background
├── Export/
│   ├── ExportManager.swift    # PNG, PDF, clipboard
│   └── ShareManager.swift     # NSSharingService
├── Settings/
│   ├── AppSettings.swift      # UserDefaults-backed settings store (injectable)
│   ├── SettingsWindow.swift   # preferences window (Settings package)
│   └── ThemeManager.swift     # predefined themes
├── Models/
│   ├── Theme.swift
│   ├── Language.swift
│   ├── SnapshotConfig.swift
│   └── GlobalShortcuts.swift  # KeyboardShortcuts.Name definitions
├── Support/
│   └── AppDefaults.swift      # UserDefaults routing (real app vs isolated UI tests)
└── Resources/
    ├── Assets.xcassets
    ├── Info.plist
    └── Vitrine.entitlements
```

## Libraries

| Library             | How to add                                                   | For                                                   |
| ------------------- | ------------------------------------------------------------ | ----------------------------------------------------- |
| `Highlightr`        | SPM ([raspu/Highlightr](https://github.com/raspu/Highlightr)) | Syntax highlighting (Highlight.js — 160+ languages)   |
| `KeyboardShortcuts` | SPM ([sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)) | Configurable global hotkey                             |
| `Settings`          | SPM ([sindresorhus/Settings](https://github.com/sindresorhus/Settings)) | The standard macOS Preferences pattern                |
| AppKit / SwiftUI / `ImageRenderer` | Built-in                                      | `NSStatusItem`, `NSTextView`, `NSPasteboard`, UI, View→PNG |

**Why Highlightr and not swift-syntax:** swift-syntax only covers Swift; Highlightr
supports 160+ languages via Highlight.js (battle-tested). Enough for v0.1; later it
could be complemented with Tree-sitter.

## Data model

```swift
// Models/SnapshotConfig.swift — everything that defines the final image
struct SnapshotConfig {
    var code:         String = ""
    var language:     Language = .swift
    var theme:        Theme = .oneDark
    var fontName:     String = "JetBrains Mono"
    var fontSize:     Double = 14
    var padding:      Double = 32
    var background:   BackgroundStyle = .gradient(.ocean)
    var showChrome:   Bool = true
    var cornerRadius: Double = 8
    var shadowRadius: Double = 20
}

enum BackgroundStyle { case solid(Color); case gradient(GradientPreset); case transparent }

enum GradientPreset: String, CaseIterable {
    case ocean = "Ocean", sunset = "Sunset", forest = "Forest", night = "Night", carbon = "Carbon"
}

struct Theme: Identifiable, Hashable {
    let id: String, displayName: String, hlJsTheme: String
    let background: Color
    static let oneDark = Theme(id: "one-dark", displayName: "One Dark",
                               hlJsTheme: "atom-one-dark", background: .init(hex: "#282C34"))
    // github, nightOwl, dracula, monokai, solarized…
    static let all: [Theme] = [.oneDark, .github, .nightOwl, .dracula, .monokai, .solarized]
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
