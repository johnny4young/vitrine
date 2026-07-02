# Vitrine — Deep Project Review (2026-07-02)

A full-project review across security, correctness, performance, architecture,
maintainability, and engineering infrastructure, produced by six parallel focused
review passes over the entire source tree, plus a synthesis of product direction.
Findings were verified against the code (file:line) before being recorded here.

**Legend:** ✅ implemented in the PR that introduced this document ·
🔧 recommended, needs a Mac/Swift toolchain to implement and verify ·
📋 recommended, decision or larger effort.

**Overall verdict.** Vitrine is an unusually disciplined codebase for an indie macOS
app: versioned settings schema with defensive decoding, injectable `UserDefaults`
everywhere, a golden-image regression suite with a pinned-runner manifest, a
checksum-pinned vendored Sparkle, a 570-key string catalog at 100% for en/es, a
23.6k-line test suite over 32.8k lines of app code, and a real privacy posture
(sandboxed, no network entitlement in the core, no-PII logging rules that call
sites actually honor). The findings below are mostly drift, scale-pressure, and
hardening gaps — not structural rot. No critical vulnerability was found.

---

## 1. Security

### 1.1 High

- **S1 — SecretScanner left PEM private-key bodies unredacted.** ✅ *fixed in this PR.*
  `Vitrine/Models/SecretScanner.swift` scanned per line, and the `private-key` rule
  matches only the `-----BEGIN … PRIVATE KEY-----` banner — one-click redaction
  blurred the banner and left 20–40 lines of actual key material legible, the exact
  credential-leak the feature exists to prevent. The scanner now carries a PEM-block
  flag across lines and reports every line through the `-----END …` banner (or EOF
  for an unterminated block). Covered by two new `SecretScannerTests` cases.

- **S2 — Third-party GitHub Actions are pinned by mutable tag, not commit SHA, in the
  workflow that holds every signing secret.** 📋 *partially mitigated in this PR.*
  `release.yml` runs `maxim-lobanov/setup-xcode@v1` and `softprops/action-gh-release@v3`
  (plus `actions/*@vN` everywhere) while the `publish` job holds the Developer ID
  `.p12`, the notary `.p8`, `SPARKLE_EDDSA_PRIVATE_KEY`, `VITRINE_LICENSE_SIGNING_KEY`,
  and `TAP_DEPLOY_KEY`. A hijacked tag on a community action is a direct supply-chain
  path to the code-signing and auto-update keys (the tj-actions incident pattern).
  *Done here:* the imported signing keychain is now deleted (and the search list
  restored) in an `always()` step immediately after the DMG build, so no later step
  or third-party action can read the identity; `.github/dependabot.yml` now tracks
  action updates weekly. *Still to do (needs trusted network access to resolve tag →
  SHA):* replace every `uses: owner/action@vN` with the full 40-char commit SHA and a
  `# vN.n.n` comment. Dependabot keeps SHA pins fresh once they exist.

### 1.2 Medium

- **S3 — "Use my logged-in session" web capture uses the shared persistent WKWebView
  data store.** 🔧 `URLRenderer.dataStore(for:)` returns `WKWebsiteDataStore.default()`
  when the (off-by-default, disclosed) opt-in is on. The setting is sticky and coarse:
  once enabled for one dashboard capture, later captures of arbitrary public URLs run
  with the persistent cookie jar. Recommendation: scope the persistent store per
  capture/host, or expire the opt-in per session, and show an active-session indicator
  in the capture UI.

- **S4 — DNS-rebinding residual risk in URL capture.** 📋 The SSRF blocklist
  (`WebSnapshotConfig.isPrivateLocalhost` + per-navigation re-checks in `URLRenderer`)
  is a pre-resolution host-string check, as its own comments document. A public
  hostname that resolves to 169.254.169.254 / RFC1918 bypasses it because WebKit
  resolves DNS itself. Hard to fully close inside WKWebView; keep the first-use
  disclosure, consider a pre-flight resolve-and-check, and record it as accepted
  residual risk.

- **S5 — Pasted HTML with a `file:` base URL can render local files into the image.**
  🔧 `WebSnapshotView` allows `file:` subresources when a `localBaseURL` is supplied
  (the content-rule list only blocks http(s)/ws(s)). Exposure is limited today because
  `HTMLRenderer` defaults `baseURL` to nil, but the engine permits it. Recommendation:
  confine `file:` access to the base URL's own directory (`loadFileURL(_:allowingReadAccessTo:)`
  semantics).

### 1.3 Low

- **S6 — Sparkle version + tarball SHA-256 were duplicated in two files kept in sync by
  hand** (`scripts/fetch-sparkle.sh` and `release.yml`). ✅ Both now source the single
  pin in `scripts/sparkle-version.env`. Additionally, `fetch-sparkle.sh` skipped the
  fetch whenever `Vendor/Sparkle.framework` existed, so bumping the pin silently kept
  the old framework; it now stamps `Vendor/.sparkle-version` and re-fetches on mismatch. ✅
- **S7 — Lemon Squeezy activation errors are logged verbatim at `privacy: .public`**
  (`LicenseActivation.swift:209-211`). 🔧 Log a typed reason instead, matching the
  no-PII discipline used everywhere else.
- **S8 — CLI license token trusts a fixed user-writable path.** 📋 By design (documented
  honor model): only a token signed by the pinned production Ed25519 key verifies, so
  the residual risk is seat-sharing, which the docs accept. Option if ever tightened:
  bind a machine identifier into the signed payload.

### 1.4 What is already strong (keep it that way)

Ed25519 license verification checks the signature before decoding the payload and
fails closed on any malformation; tokens live in the Keychain
(`…ThisDeviceOnly`, no iCloud) with a 0600 atomic CLI mirror. Pasted-HTML rendering
blocks remote loads with a compiled `WKContentRuleList` and **fails closed** if the
rule list will not compile. The SSRF blocklist covers loopback, RFC1918, CGNAT,
link-local (incl. the cloud-metadata IP), IPv6 ULA/link-local, IPv4-mapped IPv6, and
legacy `inet_aton` literals, re-checked on every navigation/redirect. Diagnostics
export copies only enum/number/bool knobs — never code, clipboard, or paths. The
sandbox entitlement set is minimal and drift-guarded by tests; the App Store build
strips Sparkle and fails if any payload remains; the appcast is EdDSA-signed with the
private key fed on stdin. `EditorHandoff` IPC uses a fresh UUID pasteboard cleared
after a one-shot read. Debug PRO unlocks are `#if DEBUG`-only.

---

## 2. Engineering infrastructure (CI / tests / release)

- **I1 — No `timeout-minutes` on 4 of 5 macOS jobs.** ✅ Added: 60 min on CI build,
  release verify, and App Store archive; 90 min on publish (double notarization
  round-trip). The repo itself documents the SPM-resolution hang mode this guards.
- **I2 — Token permissions.** ✅ `ci.yml` now sets `permissions: contents: read`
  workflow-wide; `release.yml` defaults to read-only and elevates only the `publish`
  job (`contents: write`, `pages: write`, `id-token: write`). `verify` no longer runs
  tests with a write-capable, OIDC-minting token.
- **I3 — `cancel-in-progress: true` also cancelled in-flight `main` builds,** leaving
  merged commits without a completed run. ✅ Now cancels superseded runs only for
  pull requests.
- **I4 — No fast Linux gate.** ✅ New `checks` job on `ubuntu-latest` (~30 s, before
  any macOS minutes): shellcheck over `scripts/*.sh`, workflow YAML parse (moved off
  the macOS runner), `make changelog-check`, and a golden manifest ↔ fixture
  cross-check that fails if a pinned scenario has no committed PNG (or vice versa) —
  the gap that would silently downgrade the strict pixel diff to render-only coverage.
- **I5 — `record-goldens.sh` died with no message when the recorder printed no
  `GOLDEN OUTPUT` line** (`set -e` killed the assignment before the error block —
  dead code). ✅ Fixed; the recorder run is also now serialized with the same
  CoreText pin as `make test`.
- **I6 — The CoreText-race mitigation was applied inconsistently.** ✅
  `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1` now also covers `make perf`, the
  CI golden step, and the golden recorder. 📋 The env var is an experimental toolchain
  knob; the durable fix is `.serialized` traits on the CoreText-heavy suites.
- **I7 — Coverage was gathered but never surfaced.** ✅ CI now prints the per-target
  `xccov` report into the job summary (best-effort, never fails the gate). 📋 Optional
  next step: a minimum-percentage gate.
- **I8 — The DMG shipped without an `/Applications` symlink,** contradicting the QA
  checklist's drag-to-install step. ✅ `build-dmg.sh` now stages the volume with the
  app (copied via `ditto` to keep the signed bundle bit-perfect) plus the symlink.
- **I9 — `altool --validate-app` is deprecated** (`appstore.yml`). 🔧 Migrate the dry
  run to App Store Connect API tooling before a future Xcode image drops the verb.
- **I10 — Release pipeline extras.** 📋 Worth adding when releases warrant it:
  build-provenance attestation on the DMG, an SBOM asset, and a post-publish job that
  downloads the published DMG and runs `scripts/qa-release.sh` (its exit codes already
  distinguish signing vs app failures).
- **I11 — `brew install xcodegen` is unpinned in 5 jobs.** 📋 Same drift class the
  weekly job exists to catch; pin a version (checksummed binary, mirroring the
  fetch-sparkle pattern) if a generation change ever bites.
- **I12 — Small fixes.** ✅ Stale `TEST_UI_SKIP` comment in the Makefile corrected;
  `qa-release.sh` now removes its temp mountpoint dir on exit.

Verified during review (no action): all 6 golden scenario PNGs **are** committed and
match the manifest; the Makefile's `.PHONY` list, `DEVELOPER_DIR` fallback, and
result-bundle plumbing are correct; `update-homebrew-tap.sh` is validation-first and
bash-3.2-clean; UI tests are genuinely wired into CI (31 tests, 60-min cap, failure
classification).

---

## 3. Dependencies & reproducibility

- **D1 — SPM dependencies float; no lockfile is committed.** 📋 *Highest-priority
  decision in this review.* `project.yml` uses `from: "2.3.0"` (Highlightr) and
  `from: "2.4.0"` (KeyboardShortcuts); the resolved state lives only inside the
  generated, git-ignored `.xcodeproj`, and `.gitignore` *claimed* a `Package.resolved`
  was committed (comment fixed in this PR ✅). Consequences: releases are not
  reproducible, and a Highlightr minor bump (which embeds Highlight.js) can change
  tokenization and invalidate the golden baseline with no code change. Fix on a Mac:
  either pin `exactVersion:` in `project.yml` to the currently-resolved versions, or
  commit a `Package.resolved` and copy it into the generated project in `make
  project`. Not done headlessly here because pinning blind (without knowing the
  currently-resolved versions the goldens were recorded against) risks *changing*
  the dependency set this repo actually builds with.

---

## 4. Architecture & maintainability

The layering is genuinely clean — `Canvas/` never touches settings stores, `Settings/`
never reaches into render internals, and render flows take value types
(`SnapshotConfig`, `SocialCardModel`), which is why the CLI and App Intents reuse the
export path unchanged. Error handling is consistent (zero empty catch blocks; the
`try?` clusters are the documented defensive-decode pattern). Findings:

- **A1 — `AppSettings` is a managed god object** (~508 lines, 18 persisted knobs +
  live config + social-card model + per-window sessions + presets + diagnostics).
  📋 Continue the existing `WebCaptureSettings` sub-store precedent: extract
  `ExportSettings` and a `SocialCardStore`, and move per-window session machinery to
  `State/`. Also inject `Entitlements`/`BrandKitStore` through `init` (the
  constructor-injection habit already exists) so `exportConfig` is unit-testable.
- **A2 — `WebSnapshotConfig.swift` (816 lines) mixes eight concerns,** including the
  security-relevant URL/SSRF validation and the network-capability gate, and is the
  one WebRendering file special-cased into the CLI target (`project.yml`). 📋 Split
  into config + `WebURLValidation` + `NetworkCapability`; the CLI then includes only
  the config, shrinking the special case.
- **A3 — Three parallel copy/save/share + HUD flows** (Editor, SocialCards,
  WebSnapshot editors). The Web path has already drifted: it re-implements the
  pasteboard write and save panel inline and **skips the CS-048 privacy-logging
  rule** on failure. 🔧 Extract an `ExportFeedback` helper + a data-taking
  `ExportManager.saveToFile` overload; ~80 duplicated lines disappear and the logging
  rule re-unifies.
- **A4 — Misplaced/junk-drawer files.** 📋 Quick wins on a Mac: split
  `Models/Preferences.swift` (it holds `HotkeyAction`/`ExportFormat`/`ColorProfile` —
  nothing "Preferences"); split `DesignSystem/TokenComponents.swift` (17 unrelated
  components, 769 lines); co-locate the cross-folder `VitrineCommand` extensions.
- **A5 — Flat 73-file `Tests/` directory.** 📋 Folder by module (`project.yml`
  ingests the path recursively — zero config); keep the golden infra in its own
  subfolder.
- **A6 — Docs drift.** ✅ Fixed in this PR: `ARCHITECTURE.md` now lists the missing
  `Terminal/` module and the three missing `Export/` files, and the stale
  `SnapshotConfig` snippet (which under-described the render contract by ~15 fields)
  is replaced by a pointer to the normative source. 📋 Optional guard: a CI grep that
  fails when a top-level `Vitrine/<Dir>` is absent from `ARCHITECTURE.md`.
- **A7 — Small consistency nits.** 🔧 `StoreKitProvider` purchase failures return
  `.failed` with no log (add domain/code logging); CLI batch mode counts per-file
  failures as `skipped` without printing which file/why to stderr.

---

## 5. Bugs & correctness (focused pass)

No crashes were found reachable from malformed input — the force-unwrap/`try!`/`as!`
sweep came back clean and the defensive-decoding discipline (settings migration
v1→v11, license verify path, RecentsStore eviction, export color-space math) holds
up under scrutiny. Real bugs that survived verification:

- **B1 — PEM redaction miss** — see S1. ✅ Fixed (+2 tests).
- **B2 — Line-mode ANSI parser leaked a stray byte for charset designations.** ✅
  Fixed (+test). `ESC ( B` (emitted by `tput sgr0`, so present in most `script`
  captures) only dropped two bytes, leaving a spurious `B` in the rendered image
  and sidecar text. The parser now consumes intermediate bytes 0x20–0x2F plus the
  final byte, mirroring the grid emulator.
- **B3 — Colon-form SGR parameters were misread as a full style reset.** ✅ Fixed
  (+test). `ESC[38:5:196m` (tmux, fish ≥3.4, modern emitters) parsed as code 0 and
  wiped accumulated attributes; unparseable fragments are now ignored (empty
  fragments still mean 0, per convention). Full colon-subparameter support remains
  a 📋 follow-up.
- **B4 — A C0 control inside a CSI body was swallowed into the parameter string.**
  ✅ Fixed (+test). A capture truncated mid-escape (`ESC[31\nm`) silently merged
  two output lines; the scanner now aborts the sequence and lets the control byte
  render.
- **B5 — UTF-8 BOM was not stripped from loaded files.** ✅ Fixed (+test). The
  `.utf8` decode kept the invisible U+FEFF (the `.utf16` path strips its BOM), which
  leaked into the editor, detection, and sidecars.
- **B6 — Partial hex scans decoded wrong-but-accepted colors.** ✅ Fixed (+test).
  `Color(hex: "12GG34")` decoded the partial value (and the DEBUG assert never
  fired); it now takes the documented black fallback. `HexColor` accepted fullwidth
  hex digits (`isHexDigit` is Unicode-wide) that stopped the scanner mid-string; it
  now requires ASCII.
- **B7 — `EditorWindowState.config` did not clamp `shadowRadius`** despite its doc
  saying every numeric field is clamped on restore — a corrupt restoration blob
  (`1e12`) reached `.shadow(radius:)` and forced a pathological blur allocation. ✅
  Fixed: new `SettingsDefaults.clampShadowRadius` (0…40, the inspector slider's
  range) applied on restore.
- **B8 — Reindent-on-paste corrupts multi-line string literals.** 🔧 In
  `CodeFormatter.reindent`, string-masking state (`stringQuote`) resets per line, so
  a JS template literal or Swift `"""` spanning lines gets its continuation lines
  re-indented (string *content* changes) and braces inside literals shift depth.
  `reindentOnPaste` defaults to on. Fix: carry the multi-line-capable delimiter
  state across lines (like `inBlockComment`); needs the `CodeEditorReindentTests`
  suite run before landing.
- **B9 — One malformed preset discards the whole array.** 🔧 `StylePresetDocument`
  and `PresetStore.readUserPresets` decode all-or-nothing: one corrupt entry
  collapses a 10-preset file to `[]` (reported misleadingly as "empty") and can wipe
  all user presets on next launch. Fix: lossy element-wise decode
  (`FailableDecodable` wrapper + `compactMap`).
- **B10 — Wide characters overflow a `columns == 1` terminal grid** (reachable via
  `vitrine render --terminal-width 1` with CJK/emoji input). 🔧 Guard the degenerate
  width in `TerminalScreen.putChar`. Cosmetic-severity.

## 6. Swift 6 concurrency (focused pass)

No `nonisolated(unsafe)`, no `@unchecked Sendable`, no semaphores, no legacy
`NSKeyedArchiver`/`lockFocus`, no deprecated `onChange` forms; continuations were
audited and none leak (single-resume guards + armed timeouts). Nothing found is a
genuine data race. Items worth fixing, in order:

- **C1 — Services menu uses the legacy TIFF/`NSBitmapImageRep` round-trip**
  (`CodeImageService.swift:116-121`) — an explicit AGENTS.md legacy-API violation
  that double-encodes on the main actor and can lose the deliberate sRGB tagging
  `ExportManager.pngData` guarantees. 🔧 Route through the existing ImageIO path.
- **C2 — HTML capture is not cancellation-aware** — the URL path's `LoadCoordinator`
  wraps its continuation in `withTaskCancellationHandler`; the HTML path's
  `NavigationCoordinator` does not, so Cancel is a no-op for up to 10 s per HTML
  viewport in a batch. 🔧 Mirror the URL path (mechanical; resume is already
  idempotent).
- **C3 — PRO multi-size export runs render→encode→write for every preset in one
  uninterrupted main-actor call** — all presets selected at 2–3× scale beachballs
  the app until the loop ends. 🔧 Keep renders on main, hop encode+write per preset
  off-main (or at minimum `await Task.yield()` between presets) and show progress.
- **C4 — Minor modernizations.** 📋 The one `Task.detached` (code formatting) would
  be `@concurrent nonisolated` in idiomatic 6.2; two `DispatchQueue.main.async`
  sites (deferred window close; `WindowAccessor` polling) work but predate the
  house style; background/foreground image import does `Data(contentsOf:)` + decode
  of arbitrary user images on the main actor (move to a `@concurrent` helper and
  validate via `CGImageSource`).

## 7. Performance (focused pass)

The render path already meets a documented, CI-enforced latency budget
(`PerformanceTests`: 300 ms target, hard ceiling, PERF WARN annotations), and prior
perf audits left real caches in place (highlight/bridge/terminal FIFO caches,
Recents thumbnail cache, board thumbnails). What remains, by user-visible impact:

- **P1 — Image backgrounds re-read + re-decode from disk on every preview
  invalidation.** 🔧 `BackgroundImageStore.image(for:)` is `NSImage(contentsOf:)`
  with no cache, called from SwiftUI `body` in three hot places; the framed-image
  path additionally forces a full bitmap decode per body pass to sample the chrome
  color. With a multi-MB photo, every keystroke/slider tick does main-thread file
  I/O + decode. Fix: an `NSCache` keyed by the content-addressed `fileName` (the
  same fix `RecentsStore` already got), plus caching the sampled `FrameChrome`.
  *The single worst hot path for the image features.*
- **P2 — Settings previews rasterize a full `ImageRenderer` canvas inside `body`**
  (`StyleSettingsView`, `CustomThemeEditor` at scale 2) — a color-picker drag
  re-renders the slowest path in the app per frame. 🔧 Debounce into `@State` via
  the existing `Debouncer`; render the thumbnail at scale 1.
- **P3 — Custom-theme highlighting is uncached and routed through the AppKit HTML
  importer** per body pass (JS tokenize + `NSAttributedString(html:)`, one of the
  slowest paths on macOS), so typing with a custom theme costs 50–200+ ms per pass
  on a few-hundred-line file. 🔧 Key the caches on palette value (it is hashable)
  and replace the HTML importer with direct span walking.
- **P4 — Full-document re-highlight + `setAttributedString` per 100 ms debounce
  tick** in the editor text view — typing latency spikes on 1–2k-line pastes. 🔧
  Ranged re-highlight or off-main computation with an unchanged-text check.
- **P5 — Quick capture renders the same config up to 3× synchronously on the hotkey
  path** (copy renders, save renders again, Recents thumbnail renders a third
  time) — ~600–900 ms of main-thread work against the "feels instant" promise. 🔧
  Render the `CGImage` once; derive pasteboard bytes, file bytes, and a downscaled
  thumbnail from it.
- **P6 — Multi-viewport web capture is strictly sequential** (4 viewports = 4× wall
  clock). 🔧 Design change: overlap loads with a small-cap task group — WKWebView is
  main-actor bound but each view has its own web-content process; needs runtime
  determinism validation.
- **P7 — Every keystroke persists the whole style block** (~15 `defaults.set` + 3
  JSON encodes) even though `code` is not persisted. 🔧 Skip persistence when only
  content fields changed — or split `SnapshotConfig` into style vs content
  observables, which also structurally reduces SwiftUI invalidation storms (the
  whole inspector re-evaluates per keystroke today).
- **P8 — Smaller:** gutter re-splits the attributed document per body pass (cache
  next to the highlight cache); terminal renders convert fonts per run (memoize the
  4 bold/italic variants) and materialize the scalar array 4×; `applicationWillUpdate`
  DFS-walks all window view trees until the status button is found (bound the
  search). 📋 CI guardrail: add a custom-theme fixture and a terminal fixture to
  `PerformanceTests` — none of P1–P6 would be caught by the suite today.

---

## 8. Toward a world-class app — strategic recommendations

1. **Pin the world (D1, S2).** Reproducible releases and SHA-pinned actions are the
   two highest-leverage hardening moves left; everything else is already unusually
   solid. The golden-image suite's value depends on the syntax-highlighting
   dependency not floating underneath it.
2. **Extract `VitrineCore` as a local SwiftPM package** (Models, Terminal,
   SettingsCodec/Schema, CLIArguments — already UI-free by discipline). The compiler
   then *enforces* the layering that convention currently protects, `swift test`
   runs the core without an app host (and could run on Linux CI), and the CLI's
   include-list special cases disappear. Prerequisite: push the `SwiftUI.Color`
   bridging out of `Models/`.
3. **A composition root instead of 22 `static let shared`s.** Keep the lifetimes,
   construct them in one place as an `AppEnvironment`, pass via `@Environment`. The
   codebase already injects `defaults:`/`provider:` everywhere; this is the last 10%
   that makes the action layer (copy → HUD → close) unit-testable.
4. **Privacy-preserving product insight.** Extend the existing user-initiated
   `DiagnosticsBundle` with local-only feature-usage counters surfaced in About
   ("your stats") — insight with zero telemetry, consistent with the product promise.
5. **Docs-as-tests.** The repo already tests its release process and workflows;
   extend the same muscle to `ARCHITECTURE.md` module coverage (A6) so docs can't
   drift again.
6. **Product direction.** The competitive research in `FEATURE-IDEAS.md` (39 ideas +
   a new batch of 30 integration/input/output ideas added with this review) points
   the same way: own the terminal-rendering category, make configs shareable
   (deep-link scheme → Raycast/VS Code/Xcode companions), and close the
   "viewers can't copy the code" gap — those compound the existing moats (native,
   instant, private) rather than chasing web-app parity.

---

## 9. Changes shipped with this review

| Area | Change |
| --- | --- |
| Security | SecretScanner redacts full PEM private-key blocks (+2 tests) |
| Bug | ANSI parser: charset designations (`ESC ( B`) no longer leak a stray byte (+test) |
| Bug | ANSI parser: colon-form SGR params no longer misread as a full reset (+test) |
| Bug | ANSI parser: C0 control inside a CSI body aborts the sequence instead of being swallowed (+test) |
| Bug | UTF-8 BOM stripped when loading files (+test) |
| Bug | `Color(hex:)` falls back to black on partial scans; `HexColor` rejects non-ASCII hex digits (+test) |
| Bug | Window restore clamps `shadowRadius` (new `SettingsDefaults.clampShadowRadius`, 0…40) |
| Security | Release job deletes the signing keychain right after the DMG build (`always()`) |
| Security | Sparkle version/SHA single-sourced in `scripts/sparkle-version.env`; stale-Vendor re-fetch via `.sparkle-version` stamp |
| CI | Read-only token defaults; job-level elevation only for `publish` |
| CI | `timeout-minutes` on all macOS jobs |
| CI | PR-only `cancel-in-progress` |
| CI | New Linux `checks` job: shellcheck, workflow YAML parse, changelog lockstep, golden manifest↔fixture cross-check |
| CI | Per-target coverage report in the job summary |
| CI | CoreText serialization pin on the golden step; also on `make perf` and the recorder |
| CI | `.github/dependabot.yml` for weekly grouped action updates |
| Release | DMG volume now contains the `/Applications` drag-to-install symlink (staged via `ditto`) |
| Scripts | `record-goldens.sh` no longer dies silently when the recorder prints no output line |
| Scripts | `qa-release.sh` cleans up its temp mountpoint |
| Docs | `ARCHITECTURE.md`: `Terminal/` module + missing `Export/` files documented; stale `SnapshotConfig` snippet replaced with a pointer to the normative source |
| Docs | `.gitignore` no longer claims a `Package.resolved` is committed; pinning tracked as D1 |
| Docs | This review document; `FEATURE-IDEAS.md` batch 2 (30 further realizable ideas) |
| Makefile | `perf` serialized like `test`; stale `TEST_UI_SKIP` comment fixed |
