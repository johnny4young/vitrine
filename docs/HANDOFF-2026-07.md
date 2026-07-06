# Handoff — continuing the deep-review branch on a Mac

> Written to hand a cloud session's work to a **local Mac session**. The cloud work
> was authored without a Swift toolchain, so this is the "now verify it for real and
> finish the Mac-only items" checklist. Delete this file once the branch is merged.

- **Branch:** `claude/project-deep-review-0vypec`
- **Open PR:** [#51](https://github.com/johnny4young/vitrine/pull/51) — `mergeable_state: clean`, CI green
- **Head at handoff:** `ea5b9fb` · **Base:** `main` (`777c8b5`) · 34 commits, ~+2.8k/−1k, 73 files
- **App version:** `MARKETING_VERSION 0.20.0` (unchanged; all new work is under CHANGELOG `[Unreleased]`)

## 0. Get the branch locally

```sh
git fetch origin claude/project-deep-review-0vypec
git checkout claude/project-deep-review-0vypec
make project          # regenerate Vitrine.xcodeproj from project.yml (also fetches Sparkle)
```

## 1. Verify what the cloud couldn't (do this first)

The cloud session never compiled or ran anything — CI did. Reproduce locally:

```sh
make format           # should be a no-op; if it reformats anything, commit it
make lint             # Apple swift-format --strict; must pass
make build            # headless Debug compile
make test             # full unit suite (~1000+ tests, ~25 s) — the ~30 new tests live here
make build-ui-tests   # UI tests compile
```

Then **run the app from Xcode (▶︎)** and eyeball the changes that have no unit-test
coverage for their runtime behavior — these are the ones a green CI does *not* fully vouch for:

- **HEIC export** — pick HEIC in Settings → Output and in the editor's format picker; save and confirm the `.heic` opens in Preview at the expected size.
- **Smarter save names** — Save from the editor with a `metadata.filename` set, and with code containing a `func`/`class`; confirm the proposed name.
- **Multi-line-string reindent (B8)** — paste JS with a backtick template literal and Swift with a `"""` block; confirm the interior lines are untouched and surrounding code re-indents.
- **P1 image cache** — set a photo background and scrub a slider; confirm no per-frame hitch (the point of the change).
- **P7** — type in the editor; confirm settings still persist correctly on a real style change (theme/padding/background), and that a code-only edit doesn't.
- **`vpane`** — inside tmux, `eval "$(vitrine shell-init zsh)"` then `vpane`.
- **asciinema import** — drop a real `.cast` file onto the editor.

## 2. Mac-only backlog (in priority order)

These are documented in **`docs/DEEP-REVIEW-2026-07.md`** with `file:line` evidence.
The two structural ones are worth doing before the next release:

1. **Pin SPM dependencies (D1 — highest priority).** Releases aren't reproducible and a
   Highlightr minor bump can silently invalidate the golden images.
   - After `make project`, read the resolved versions from the generated project's
     `Package.resolved`, then either set `exactVersion:` in `project.yml` (Highlightr,
     KeyboardShortcuts) or commit a `Package.resolved` and copy it in `make project`.
   - Re-run `make test` to confirm the goldens still pass at the pinned versions.
2. **SHA-pin the GitHub Actions (S2).** In `.github/workflows/*.yml`, replace every
   `uses: owner/action@vN` with the full 40-char commit SHA + a `# vN.n.n` comment.
   Dependabot (`.github/dependabot.yml`, already added) keeps them fresh once pinned.
   The cloud session couldn't do this — the sandbox proxy blocked resolving the SHAs.
3. **Performance P2/P4/P5/P6** — debounce Settings previews, ranged re-highlight,
   quick-capture render-once, parallel multi-viewport web capture. Each needs profiling
   and visual/concurrency validation. Add a custom-theme and a terminal fixture to
   `PerformanceTests` as a guardrail first.
4. **Larger refactors** — `AppSettings` sub-stores (follow the `WebCaptureSettings`
   precedent), a composition root instead of the 22 `static let shared`, then a
   `VitrineCore` local SwiftPM package. Order matters: each enables the next.
5. **C1** (Services menu still uses the legacy TIFF/`NSBitmapImageRep` round-trip that
   AGENTS.md forbids), **C3** (multi-size export runs encode+write on the main actor),
   and caching the sampled `FrameChrome` (the framed-image per-body bitmap decode).

## 3. Landing the PR

- Review the diff (34 commits) — consider reviewing by area: `Vitrine/Terminal`,
  `Vitrine/Editor`, `Vitrine/Export`, `Vitrine/WebRendering`, `.github/workflows`.
- Squash-or-merge per your preference; the commits are conventional and self-contained,
  so a merge (not squash) keeps a readable history.
- After merge, delete this file and `docs/DEEP-REVIEW-2026-07.md`'s "implemented" items
  can be trimmed to just the remaining backlog if you want a shorter living doc.

## Where things are

- **Review report:** `docs/DEEP-REVIEW-2026-07.md` (✅ done / 🔧 needs Mac / 📋 larger)
- **Feature backlog:** `docs/FEATURE-IDEAS.md` (69 ideas, batch 2 at the bottom)
- **Conventions:** `AGENTS.md` (Swift 6, MainActor-default, no legacy APIs, clean-English prose, no AI trailers)
- **CI:** `.github/workflows/ci.yml` (build + UI + the new Linux `checks` job), `release.yml`, `appstore.yml`
