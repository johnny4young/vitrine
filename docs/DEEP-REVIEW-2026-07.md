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
  workflow that holds every signing secret.** ✅ *fixed in this PR.*
  `release.yml` ran `maxim-lobanov/setup-xcode@v1` and `softprops/action-gh-release@v3`
  (plus `actions/*@vN` everywhere) while the `publish` job holds the Developer ID
  `.p12`, the notary `.p8`, `SPARKLE_EDDSA_PRIVATE_KEY`, `VITRINE_LICENSE_SIGNING_KEY`,
  and `TAP_DEPLOY_KEY`. A hijacked tag on a community action is a direct supply-chain
  path to the code-signing and auto-update keys (the tj-actions incident pattern).
  *Done here:* the imported signing keychain is now deleted (and the search list
  restored) in an `always()` step immediately after the DMG build, so no later step
  or third-party action can read the identity; `.github/dependabot.yml` tracks
  action updates weekly. *Completed on a Mac:* all 25 `uses:` references across
  `ci.yml`, `release.yml`, and `appstore.yml` are now pinned to the full 40-char
  commit SHA with a trailing `# vN.n.n` comment (Dependabot rewrites both when it
  bumps), and a new `WorkflowConfigurationTests.thirdPartyActionsArePinnedToCommitSHAs`
  guard fails the suite if any workflow ever reverts to a mutable tag.

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
- **S7 — Lemon Squeezy activation errors were logged verbatim at `privacy: .public`**
  (`LicenseActivation.swift`). ✅ *Implemented:* the server-refusal catch now logs a
  typed reason plus the message length only (never the external text), matching the
  no-PII discipline used everywhere else; a test pins the `.server → .invalidKey`
  outcome so the mapping survives the log change.
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
- **I10 — Release pipeline extras.** ✅ *Mostly implemented:* the DMG now gets a
  signed build-provenance attestation (`gh attestation verify …`), and a post-publish
  `qa` job downloads the published DMG and runs `scripts/qa-release.sh` against it
  (its exit codes already distinguish signing vs app failures; it runs after publish
  so it flags rather than blocks). 📋 Remaining: an SBOM asset.
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

- **D1 — SPM dependencies float; no lockfile is committed.** ✅ *fixed on a Mac.*
  `project.yml` used `from: "2.3.0"` (Highlightr) and `from: "2.4.0"`
  (KeyboardShortcuts); the resolved state lived only inside the generated,
  git-ignored `.xcodeproj`, and `.gitignore` *claimed* a `Package.resolved`
  was committed (comment fixed in this PR ✅). Consequences: releases were not
  reproducible, and a Highlightr minor bump (which embeds Highlight.js) could change
  tokenization and invalidate the golden baseline with no code change. *Done:* both
  packages are now pinned with `exactVersion:` to the versions the goldens were
  recorded against — Highlightr `2.3.0` (commit `05e7fcc`) and KeyboardShortcuts
  `2.4.0` (commit `1aef855`), read from the generated `Package.resolved` before
  pinning. Regenerating the project resolves to the identical commits and the full
  golden suite still passes, so the pin froze the graph without changing it.

---

## 4. Architecture & maintainability

The layering is genuinely clean — `Canvas/` never touches settings stores, `Settings/`
never reaches into render internals, and render flows take value types
(`SnapshotConfig`, `SocialCardModel`), which is why the CLI and App Intents reuse the
export path unchanged. Error handling is consistent (zero empty catch blocks; the
`try?` clusters are the documented defensive-decode pattern). Findings:

- **A1 — `AppSettings` is a managed god object** (~508 lines, 18 persisted knobs +
  live config + social-card model + per-window sessions + presets + diagnostics).
  ✅ *Partially done:* `Entitlements`/`BrandKitStore` are now injected through `init`
  (defaulting to the shared instances, so no call site changes), and `exportConfig` is
  covered by three new tests that vary the entitlement and the kit — the "last 10%" that
  makes the export-config derivation unit-testable. ✅ *Also done:* the eight image-output
  knobs (auto-copy, save, scale, format, color profile, rich clipboard, text sidecar,
  close-after-copy) are extracted into a focused `ExportSettings` sub-store on the
  `WebCaptureSettings` precedent — `settings.export.<field>`, persistence and schema
  unchanged — cutting `AppSettings` down and namespacing the output settings. 📋
  *Remaining:* a `SocialCardStore` and moving the per-window session machinery to
  `State/` (lower value; the god-object pressure is largely relieved).
- **A2 — `WebSnapshotConfig.swift` (816 lines) mixed eight concerns,** including the
  security-relevant URL/SSRF validation and the network-capability gate. ✅
  *Implemented:* validation (+ `URLValidationError` + the SSRF host blocklist) now
  lives in `WebURLValidation.swift` and the entitlement gate in
  `NetworkCapability.swift`, each independently reviewable. Note: both remain in the
  CLI's include list — the config's validating initializer depends on `validate`,
  and settings surfaces read the gate — so the reviewability goal is met while the
  CLI include list is three value-only files (documented in `project.yml`).
- **A3 — Three parallel copy/save/share + HUD flows** (Editor, SocialCards,
  WebSnapshot editors). The Web path had already drifted: it re-implemented the
  pasteboard write and save panel inline and **skipped the CS-048 privacy-logging
  rule** on failure. ✅ *Implemented:* new `Export/ExportFeedback` presenter (one
  outcome→HUD mapping, one set of strings, cancelled-save-is-silent in one place),
  a payload-taking `ExportManager.saveToFile(payload:suggestedName:)` that every
  save flow (config, social card, web) funnels through, and a shared
  `copyPNGToPasteboard(_:)` primitive — the web path now logs like every other save.
- **A4 — Misplaced/junk-drawer files.** ✅ *Implemented:* `Models/Preferences.swift`
  split into `HotkeyAction.swift` + `ExportFormat.swift` (with `ColorProfile`);
  `DesignSystem/TokenComponents.swift` (769 lines, 17 components) split into
  form primitives + `TokenButtons` + `ThemeChips` + `FontChips` + `Swatches`;
  the `VitrineCommand` SwiftUI extension co-located under `App/`.
- **A5 — Flat 73-file `Tests/` directory.** 📋 Folder by module (`project.yml`
  ingests the path recursively — zero config); keep the golden infra in its own
  subfolder.
- **A6 — Docs drift.** ✅ Fixed in this PR: `ARCHITECTURE.md` now lists the missing
  `Terminal/` module and the three missing `Export/` files, and the stale
  `SnapshotConfig` snippet (which under-described the render contract by ~15 fields)
  is replaced by a pointer to the normative source. ✅ The guard is now live: the
  Linux CI job fails when a top-level `Vitrine/<Dir>` is absent from
  `ARCHITECTURE.md`, and a companion gate fails when a String Catalog key loses its
  translated `es` entry.
- **A7 — Small consistency nits.** ✅ *Implemented:* `StoreKitProvider` purchase
  failures now log the error domain/code (non-PII) instead of returning `.failed`
  silently, and CLI batch mode names each skipped file (and why) on stderr.

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
- **B8 — Reindent-on-paste corrupted multi-line string literals.** ✅ *Implemented
  (+4 tests):* `CodeFormatter.reindent` now carries backtick-template and triple-quote
  state across lines (like `inBlockComment`), emits lines that begin inside a literal
  verbatim, and no longer counts braces inside a literal. `"`/`'` stay line-local so
  Rust lifetimes and apostrophes are still contained.
- **B9 — One malformed preset discarded the whole array.** ✅ *Implemented (+3 tests):*
  a new `Support/FailableDecodable<T>` wrapper makes `StylePresetDocument` and
  `PresetStore.readUserPresets` decode element-tolerantly — one corrupt entry drops
  itself instead of collapsing the file to `[]` or wiping all user presets on launch.
- **B10 — Wide characters overflowed a `columns == 1` terminal grid** (reachable via
  `vitrine render --terminal-width 1` with CJK/emoji input). ✅ *Implemented (+test):*
  `TerminalScreen.putChar` clamps the cell count to the grid width, so a wide char
  collapses to its head instead of writing past the margin.

## 6. Swift 6 concurrency (focused pass)

No `nonisolated(unsafe)`, no `@unchecked Sendable`, no semaphores, no legacy
`NSKeyedArchiver`/`lockFocus`, no deprecated `onChange` forms; continuations were
audited and none leak (single-resume guards + armed timeouts). Nothing found is a
genuine data race. Items worth fixing, in order:

- **C1 — Services menu used the legacy TIFF/`NSBitmapImageRep` round-trip**
  (`CodeImageService.swift`) — an explicit AGENTS.md legacy-API violation that
  double-encoded on the main actor and could lose the deliberate sRGB tagging
  `ExportManager.pngData` guarantees. ✅ *Implemented:* the Services provider now
  renders a `CGImage` (new `SnapshotRenderService.renderCGImage`) and PNG-encodes it
  through the color-managed ImageIO path (`ExportManager.pngData`), writing the
  `NSImage` object plus those bytes to the pasteboard — no TIFF round-trip.
- **C2 — HTML capture was not cancellation-aware** — the URL path's `LoadCoordinator`
  wraps its continuation in `withTaskCancellationHandler`; the HTML path's
  `NavigationCoordinator` did not, so Cancel was a no-op for up to 10 s per HTML
  viewport in a batch. ✅ *Implemented:* `NavigationCoordinator.waitForLoad` now
  mirrors the URL path (pre-suspension `Task.isCancelled` check + `onCancel` hop;
  `resume` was already idempotent).
- **C3 — PRO multi-size export ran render→encode→write for every preset in one
  uninterrupted main-actor call** — all presets selected at 2–3× scale beachballed
  the app until the loop ended. ✅ *Implemented:* `exportPresetSizes` is now `async`;
  each preset renders on the main actor (`ImageRenderer` requires it), then a
  `@concurrent nonisolated writePreset` PNG/HEIC-encodes and writes off the main actor
  (`CGImage`/`Data` are `Sendable`), with `await Task.yield()` between presets and an
  `onProgress` callback driving a live "n/total" indicator in the export sheet. A byte-
  equality test confirms the off-main encode is identical to the single-export path.
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
  invalidation.** ✅ *Implemented (+test):* `BackgroundImageStore.image(for:)` now
  serves from a process-wide `NSCache` keyed by the resolved (content-addressed, so
  immutable) path — the same fix `RecentsStore` already has — so an unchanged
  background/foreground no longer touches the disk on every `body` pass. ✅ *Also done:*
  the sampled `FrameChrome` for the framed-image path (the per-body full-bitmap decode
  in `DeviceFrames.topEdgeColor`) is now cached in `FramedImageView` by the image's
  content-addressed (SHA-256) file name, so `.auto` chrome is sampled once per image.
- **P2 — Settings previews rasterized a full `ImageRenderer` canvas inside `body`**
  (`StyleSettingsView`, `CustomThemeEditor` at scale 2) — a color-picker drag
  re-rendered the slowest path in the app per frame. ✅ *Implemented:* both previews
  now render off the `body` pass via `.task(id:)` keyed on an `Equatable` snapshot of
  the render inputs — a `Task.sleep` debounce coalesces a rapid drag into one trailing
  render, stored in `@State` — and the thumbnail renders at scale 1 (it is a ≤150 pt
  thumbnail, so scale 2 only burned pixels). The initial render still runs on appear.
- **P3 — Custom-theme highlighting is uncached and routed through the AppKit HTML
  importer** per body pass (JS tokenize + `NSAttributedString(html:)`, one of the
  slowest paths on macOS), so typing with a custom theme costs 50–200+ ms per pass
  on a few-hundred-line file. 🔧 Key the caches on palette value (it is hashable)
  and replace the HTML importer with direct span walking.
- **P4 — Full-document re-highlight + `setAttributedString` per 100 ms debounce
  tick** in the editor text view — typing latency spikes on 1–2k-line pastes.
  ✅ *Partially implemented (+2 tests):* highlighting only recolors, never changes the
  characters, so `applyHighlight` now applies the new attributes **in place** over the
  existing text storage (`beginEditing`/`endEditing`) instead of a full
  `setAttributedString` — the layout manager reuses the glyphs and re-processes only
  the changed attributes rather than re-seating every character. Selection survives
  untouched (character-index based). 📋 *Deferred (needs P3 first):* moving the
  Highlightr **tokenization** off-main is unsafe today — a custom theme renders through
  the main-thread-only AppKit HTML importer and the built-in path shares one `JSContext`
  with the canvas, so an off-main call would race it; and ranged re-highlight risks
  mis-coloring multi-line constructs. Both open up once P3 replaces the HTML importer
  with direct span walking.
- **P5 — Quick capture rendered the same config twice synchronously on the hotkey
  path** (copy renders, save renders the identical config again). ✅ *Implemented
  (+3 tests):* `QuickCapture` now renders the styled `CGImage` **once** and feeds it to
  both the clipboard copy (`copyPNGToPasteboard`, or the new
  `RichPasteboard.copy(cgImage:…)` for the rich/plain-text variant) and the file save
  (new `ExportManager.saveToFile(cgImage:format:…)` for raster). A PDF save still
  renders its own vector page. A byte-equality test pins that the single-render output
  matches the full-render path. *Note:* the Recents thumbnail is **not** a third render
  of this config — it renders a deliberately simplified default-styled capture at a
  fixed 320×200, so it is left as its own (cheaper) render rather than a downscale that
  would change the gallery's appearance.
- **P6 — Multi-viewport web capture was strictly sequential** (4 viewports = 4× wall
  clock). ✅ *Implemented:* `render(settings:)` now runs the per-viewport loads through a
  `withTaskGroup` with a small sliding-window concurrency cap (`maxConcurrentCaptures = 3`)
  — each viewport owns its `WKWebView`/web-content process, so the loads overlap even
  though `WKWebView` is main-actor bound (the `await` on each load releases the main
  actor). Results reassemble into the user's selected order for the board/preview,
  progress reports by completion count, and Cancel `cancelAll()`s the in-flight children
  (whose waits are cancellation-aware) and stops scheduling. Per-viewport output is
  unchanged (independent renderers); reviewed for data-race safety, and `renderOne` now
  routes on the immutable captured `input` rather than the live `mode`, so a mid-render
  mode toggle can't route viewports inconsistently across the parallel batch. 📋 A live 4-viewport
  capture still deserves an eyeball to confirm the wall-clock win and that a shared
  logged-in-session cookie store behaves under concurrent loads.
- **P7 — Every keystroke persisted the whole style block** (~15 `defaults.set` + 3
  JSON encodes) even though `code` is not persisted. ✅ *Implemented (+test):*
  `AppSettings.config.didSet` now compares the whole struct with `code` normalized and
  skips `persistStyle` + the preset-divergence check when only the code changed — so a
  keystroke does zero defaults churn while any real style change still persists.
  📋 Larger follow-up: split `SnapshotConfig` into style vs content observables to also
  cut the SwiftUI invalidation storm (the whole inspector re-evaluates per keystroke).
- **P8 — Smaller:** ✅ `applicationWillUpdate`'s status-button DFS is now bounded by an
  attempt budget, so a never-found button can no longer tax every event-loop pass.
  📋 Remaining: gutter re-splits the attributed document per body pass (cache next to
  the highlight cache); terminal renders convert fonts per run (memoize the 4
  bold/italic variants) and materialize the scalar array 4×. CI guardrail: add a
  custom-theme fixture and a terminal fixture to `PerformanceTests` — none of P2–P6
  would be caught by the suite today.

**Not done without a Mac (need profiling / visual / concurrency verification, since
"it compiles and tests pass" cannot confirm a runtime speed property or the absence
of a visual/behavioral regression):** P2 (debounce Settings previews — SwiftUI
timing), P3's HTML-importer replacement (the palette-keyed cache is doable; the
importer swap needs runtime), P4 (ranged re-highlight — selection/correctness risk),
P5 (quick-capture render-once — image-equality and thumbnail risk), P6 (parallel web
capture — concurrency determinism).

---

## 8. Toward a world-class app — strategic recommendations

1. **Pin the world (D1, S2).** ✅ *Done.* SPM dependencies are pinned with
   `exactVersion:` (so the golden-image suite's value no longer depends on the
   syntax-highlighting dependency floating underneath it) and every workflow action
   is SHA-pinned with a drift-guard test. These were the two highest-leverage
   hardening moves left; everything else is already unusually solid.
2. **Extract `VitrineCore` as a local SwiftPM package** (Models, Terminal,
   SettingsCodec/Schema, CLIArguments). The compiler would then *enforce* the layering
   that convention currently protects, `swift test` would run the core without an app
   host (and could run on Linux CI), and the CLI's include-list special cases would
   disappear. 📋 *Not started — the prerequisite is bigger than "push `SwiftUI.Color`
   out of `Models/`."* A dependency audit (2026-07) found `Models/` and `Terminal/` are
   **not** UI-free by discipline: `Theme` (39 `Color` refs), `Background` (23),
   `Annotation`, `SocialCardModel`, `ExportPreset`, and `Color+Hex` import SwiftUI and
   model their colors as `SwiftUI.Color`; `BackgroundImageStore`/`SnapshotConfig` import
   AppKit (`NSImage`); `CodeFont` uses `NSFont`; and `Terminal/ANSIPalette` uses
   `NSColor` **and depends on `Theme`**. So the real prerequisite is a rendering-critical
   re-architecture of the core color/image/font representation (replace `SwiftUI.Color`
   with the existing UF-free `RGBAColor` across the models and every reader, and lift the
   AppKit bridging into the UI layer) before any package boundary can be a clean cut.
   🔧 *In progress in this branch* as an incremental epic, golden-validated at each step.
   ✅ *Model layer is now SwiftUI-free (7 steps):* `RGBAColor` + the hex parser are a
   UI-free struct; `Annotation`, `Theme`/`HexColor`, `SocialCardModel`, `ExportPreset`,
   `Background` (colors → `RGBAColor`, gradient/`LinearGradient` adapters split out), and
   `SnapshotConfig`/`BackgroundImageStore` (alignment + `EnvironmentValues` split out) no
   longer import `SwiftUI` — every `SwiftUI.Color`/`LinearGradient`/`Alignment`/env bridge
   lives in a `*+UI.swift` adapter in the UI layer, and the golden suite confirms the
   render is byte-identical. The pragmatic boundary is **no SwiftUI view layer**; a few
   models keep AppKit *data* types (`NSImage`/`NSColor`/`NSFont`), so full Linux-runnability
   is a further step. 📋 *Remaining:* the physical SwiftPM package — a large mechanical step
   (public API surface across ~42 model/terminal types + their members, resolving in-package
   vs app-only references like `Log`/`SettingsDefaults`, and the `project.yml`/xcodegen
   rewire for app+CLI+tests) — which is what turns the now-explicit layering into
   *compiler-enforced* layering.
3. **A composition root instead of 22 `static let shared`s.** ✅ *Foundation done
   (+2 tests):* the data stores (`Entitlements`, `BrandKitStore`, `AppSettings`,
   `RecentsStore`, `CustomThemeStore`, `PresetStore`) are now built in one place —
   `AppEnvironment` — in a single, reviewable dependency order (entitlement + Brand Kit
   first, handed to `AppSettings`), and each `Store.shared` is a thin forwarder to that
   root. So there is one construction site and the whole graph is injectable: a test
   builds its own `AppEnvironment(defaults:)` over an isolated suite. Lifetimes are
   unchanged and every existing call site keeps working. 📋 *Remaining (incremental):*
   migrate individual `.shared` reads in the non-view action layer to the injected graph
   (the copy → HUD → close flow) and thread `AppEnvironment` through `@Environment`; the
   UI-lifecycle window controllers stay as their own singletons.
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
| Security | All 25 workflow `uses:` refs SHA-pinned (S2) + a drift-guard test that rejects any mutable `@vN` tag |
| Security | Release job deletes the signing keychain right after the DMG build (`always()`) |
| Dependencies | SPM deps pinned with `exactVersion:` — Highlightr 2.3.0, KeyboardShortcuts 2.4.0 (D1) |
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
