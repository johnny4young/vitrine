# Contributing to Vitrine

Thanks for your interest! Vitrine is MIT-licensed and contributions are welcome —
**themes and language tweaks especially.**

## Prerequisites

- macOS 14+ and **Xcode 16+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Setup

```bash
git clone https://github.com/johnny4young/vitrine.git
cd vitrine
make            # generates Vitrine.xcodeproj and opens it in Xcode
```

`Vitrine.xcodeproj` is **generated from [`project.yml`](project.yml)** and is not
committed — this avoids project-file merge conflicts and keeps the spec authoritative.
Always run `make project` after pulling changes that touch `project.yml`.

## Make targets

| Target          | Does                                                          |
| --------------- | ------------------------------------------------------------ |
| `make` / `make all` | bootstrap + generate the project + open in Xcode         |
| `make project`  | `xcodegen generate` → `Vitrine.xcodeproj`                    |
| `make open`     | open the generated project in Xcode                          |
| `make build`    | headless `xcodebuild` compile-check (Debug)                  |
| `make format`   | format Swift sources in place (Apple `swift-format`)         |
| `make lint`     | lint Swift sources (fails on issues); run in CI              |
| `make clean`    | remove the generated project and build artifacts             |

> `make` auto-detects full Xcode via `DEVELOPER_DIR` even when `xcode-select` points at
> the Command Line Tools.

## Conventions

See [AGENTS.md](AGENTS.md). In short:

- Edit `project.yml`, never the generated `.xcodeproj`.
- Swift 6, SwiftUI-first, `@MainActor`-by-default concurrency; keep the
  [`Vitrine/`](Vitrine) module layout. No deprecated APIs.
- Run `make format` before committing; `make lint` must pass.
- All committed prose (including UI strings and comments) is in **clean English**.
- Conventional, imperative commit subjects; reference `CS-0xx` tickets where relevant.
- **No AI co-authorship / "generated-by" trailers** in commits or PRs.

## Adding a theme

Themes live in `Vitrine/Models/Theme.swift` (metadata + Highlight.js theme name) and
`Vitrine/Settings/ThemeManager.swift`. Add the `Theme` value, include it in
`Theme.all`, and make sure the `hlJsTheme` matches a bundled Highlight.js theme name.

## Roadmap

Work is tracked as `CS-0xx` tickets in [docs/ROADMAP.md](docs/ROADMAP.md). Picking up
an unimplemented `// TODO: CS-0xx` is a great first contribution.
