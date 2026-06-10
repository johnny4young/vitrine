# AGENTS.md — conventions for Vitrine

Guidance for AI agents and contributors. Keep it short; only non-obvious rules live here.

## Project generation

- **`project.yml` (XcodeGen) is the source of truth.** `Vitrine.xcodeproj` is generated
  and git-ignored. After editing `project.yml`, run `make project` (or `xcodegen
  generate`). Never hand-edit the `.xcodeproj`.
- Add Swift packages and build settings in `project.yml`, not in Xcode's UI (the change
  would be lost on regeneration).
- `xcodebuild` requires full Xcode. If `xcode-select -p` points at CommandLineTools,
  prefix builds with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the
  `Makefile` already does this).

## Code

- **Swift 6** (latest language mode), SwiftUI-first, AppKit where needed.
- **Concurrency:** the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` +
  `SWIFT_APPROACHABLE_CONCURRENCY = YES` (Swift 6.2). Everything is `@MainActor` by
  default — do **not** sprinkle `@MainActor` or `nonisolated(unsafe)`; mark
  `nonisolated` only where you genuinely leave the main actor, and prefer structured
  concurrency (`async` / `AsyncStream`) over completion-handler bridging.
- **No legacy/deprecated APIs.** Use modern equivalents (e.g. `ImageRenderer` + ImageIO
  for PNG, `KeyboardShortcuts.events(_:for:)` not `on(_:for:)`).
- **Formatting:** run `make format` before committing; `make lint` must pass
  (Apple `swift-format`, configured by [`.swift-format`](.swift-format)).
- Match the module layout under `Vitrine/` (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).
- Unimplemented work is marked `// TODO: CS-0xx` referencing the local working spec.
  Keep those markers accurate.
- No network code in the core. Sandboxed without `network.client`; user content never
  leaves the Mac.

## Prose & language

- **All committed prose is in clean English** — README, docs, code comments, commit
  messages, UI strings. No Spanglish (do not mix languages in committed text). This
  applies only to committed content, not to chat.

## Commits

- **Never add AI co-authorship or "generated-by" trailers** to commits or PRs
  (no `Co-Authored-By: Claude…`, no `🤖 Generated with…`). Only on explicit request.
- Conventional, imperative subject lines (e.g. `feat(menubar): add Theme submenu`).
  Reference tickets where relevant (`CS-009`).

## Verifying a change

- `make build` for a headless Debug build.
- For UI behavior, run from Xcode (▶︎) and confirm the menu-bar icon appears with no
  Dock icon (`LSUIElement`).
