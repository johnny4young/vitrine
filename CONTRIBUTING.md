# Contributing to Vitrine

Thanks for your interest! Vitrine is MIT-licensed and contributions are welcome —
**themes and language tweaks especially.** Security issues go through
[SECURITY.md](SECURITY.md) (privately), never a public issue.
Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and usage
questions are routed through [SUPPORT.md](SUPPORT.md).

## Prerequisites

- macOS 14+ and **Xcode 16+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), installed from the verified
  release asset with `./scripts/install-xcodegen.sh`
- Node.js 22.12+ for changes under `site/`

## Setup

```bash
git clone https://github.com/johnny4young/vitrine.git
cd vitrine
./scripts/install-xcodegen.sh
export PATH="$HOME/.local/bin:$PATH"
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
| `make test`     | run the Swift Testing unit suite (~25 s)                     |
| `make build-ui-tests` | compile the UI tests (no automation permission needed) |
| `make test-ui`  | run the XCUITest smokes (first run asks for UI automation)   |
| `make cli`      | build the `vitrine` command-line renderer                    |
| `make gallery`  | regenerate the launch-gallery design-QA samples              |
| `make record-goldens` | regenerate the golden-image baseline (deliberate visual changes only) |
| `make site-test` | type-check, build, and validate the Astro website             |
| `make format`   | format Swift sources in place (Apple `swift-format`)         |
| `make lint`     | lint Swift sources (fails on issues); run in CI              |
| `make clean`    | remove the generated project and build artifacts             |

README screenshots are regenerated with the opt-in tour in
[`UITests/ScreenshotTourUITests.swift`](UITests/ScreenshotTourUITests.swift)
(set `TEST_RUNNER_VITRINE_SCREENSHOT_DIR` when running `make test-ui`).

> `make` auto-detects full Xcode via `DEVELOPER_DIR` even when `xcode-select` points at
> the Command Line Tools.

## Conventions

See [AGENTS.md](AGENTS.md). In short:

- Edit `project.yml`, never the generated `.xcodeproj`.
- Swift 6, SwiftUI-first, `@MainActor`-by-default concurrency; keep the
  [`Vitrine/`](Vitrine) module layout. No deprecated APIs.
- Run `make format` before committing; `make lint` must pass.
- All committed prose (including UI strings and comments) is in **clean English**.
- New user-facing strings go in the String Catalog **with an `es` translation**
  (`LocalizationTests` enforces it).
- App-chrome styling reads the token layer in
  [`Vitrine/DesignSystem/`](Vitrine/DesignSystem) — never hard-code a hex in a view.
- The public website lives in [`site/`](site/) and uses Astro with semantic HTML,
  vanilla CSS, and vanilla JavaScript — no React runtime.
- Conventional, imperative commit subjects without private planning identifiers.
- **No AI co-authorship / "generated-by" trailers** in commits or PRs.

## Branch and pull request workflow

Start each change from an up-to-date `main` and keep the branch focused:

```bash
git switch main
git pull --ff-only
git switch -c <type>/<short-description>
```

Open a pull request early enough for CI and review to shape the change. The repository
uses squash merges so `main` stays linear, requires all repository-owned CI jobs, and
requires review conversations to be resolved before merge. Pull request titles become
the final commit subjects, so keep them conventional, imperative, and free of private
planning identifiers.

GitHub automatically deletes the remote head branch after merge. Clean the local copy
only after GitHub shows the pull request as merged:

```bash
git switch main
git pull --ff-only
git fetch --prune
git branch -D <type>/<short-description>
```

Squash merging creates a new commit on `main`, so Git cannot prove the original local
branch tip is an ancestor; that is why the last command uses `-D`. Verify the pull
request's merged state before running it. Never reuse a merged branch for unrelated
work.

## Adding a theme

Themes live in `Vitrine/Models/Theme.swift` (metadata and Highlight.js theme name).
Add the `Theme` value, include it in
`Theme.builtIns` (kept alphabetical by display name), and make sure the `hlJsTheme`
matches a bundled Highlight.js theme name.

## Finding work

Open GitHub issues are the public source for contribution-sized work. Source `TODO`
comments must explain the missing behavior directly and must not reference private
planning documents or identifiers.
