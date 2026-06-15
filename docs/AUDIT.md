# Vitrine — Codebase Audit (2026-06-15)

Method: seven parallel review agents (security, bugs/patterns, performance, Swift-6
concurrency, UI/HIG, architecture/libraries, competitor feature research) over the full
tree plus the uncommitted PRO epic (CS-088–094) and web multi-viewport (CS-044-ext).
Findings a build/test pass would not catch — all `make build`/`cli`/`test`/`lint` are green.

Priority key: **P0** = correctness/ship-relevant before PRO goes live · **P1** = high-value
(security/perf/UX) · **P2** = refactor/architecture/docs. Each item lists `file:line` and the
fix. None block the current branch (it is green); these are the next-pass backlog.

> **Resolved 2026-06-15** (build/cli/test=1154 incl. golden suite/lint green): all four **P0**
> bugs (StoreKit lifecycle, File-menu watermark parity, the two-sheet collapse, the URL
> disclosure loop), **P1-Perf-1** (HighlightManager theme + tokenization memoization — goldens
> verified byte-identical), and **P1-Security-1/2** (license token → Keychain, CLI Hardened
> Runtime). Items below tagged `[FIXED]` are done; the rest remain open backlog. The StoreKit
> `#else` paywall path is compiled only by the App-Store-flavor build (no `VITRINE_DIRECT_DOWNLOAD`),
> not by `make test`.

---

## P0 — Bugs / ship-relevant

1. **StoreKit lifecycle is incomplete (CS-089).** Flagged independently by the bugs,
   concurrency, and architecture agents.
   - `Transaction.updates` never calls `transaction.finish()` → unfinished transactions
     re-deliver on every launch. `Vitrine/Pro/StoreKitProvider.swift:82-86` — add
     `await transaction.finish()` after `onChange()`.
   - `StoreKitProvider.startObservingUpdates(_:)` is **never called**, and
     `Entitlements.refresh()` is never called at launch → a refund (`revocationDate`) or a
     cross-device purchase does not reflect until the user manually taps Restore. Wire
     `Task { await Entitlements.shared.refresh() }` + `startObservingUpdates { … refresh() }`
     once in `AppDelegate.applicationDidFinishLaunching` (App Store build).
   - `StoreKitProvider.purchase()` swallows all errors with `try?`
     (`StoreKitProvider.swift:53-56`) → the paywall spinner clears with no feedback on a
     failed/declined purchase. Propagate a typed error and surface it in `PaywallSheet`.

2. **File-menu Save/Share/Copy do not apply the Brand Kit watermark, but the editor toolbar
   (which mirrors them) does** → same user action, different pixels by entry point. Same bug
   class as the Shortcuts/Services divergence already fixed in this branch.
   `Vitrine/App/VitrineCommands.swift:287,299,318` use `settings.config`; route them through
   `…exportConfig` like `EditorView.swift:229,283,936,947`. (QuickCapture's omission at
   `QuickCapture.swift:103` is deliberate and documented — leave it.)

3. **Two sibling `.sheet(isPresented:)` on one view** — SwiftUI honors only one per view on
   several OS versions; the second can silently never present (latent "button does nothing").
   `Vitrine/Editor/EditorView.swift:359-366` (multi-size + paywall). Collapse to a single
   `.sheet(item:)` over an enum (`.export` / `.paywall`).

4. **URL-capture disclosure can infinite-loop when the network entitlement is absent.**
   `Vitrine/WebRendering/WebSnapshotEditorView.swift:421-425` shows the disclosure when
   `!consent || !isURLCaptureEnabled`; with the feature disabled the confirm button is
   permanently disabled, so consent never sticks and every "Capture" re-shows the sheet.
   Gate on `!consent && isURLCaptureEnabled`; let the disabled build fall through to the
   existing `RenderError.urlCaptureDisabled` message.

---

## P1 — Security

1. **License token stored in `UserDefaults`, not the Keychain (H-1).**
   `Vitrine/Pro/LicenseKey.swift:114` writes the signed token to
   `~/Library/Preferences/com.johnny4young.vitrine.plist` (user-readable by any process) →
   trivial seat-sharing. The CLI token file (`CLIEntitlement.defaultTokenURL`) is likewise
   world-readable with no mode hardening. Fix: store in Keychain
   (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); write the CLI token file `0600`.
   Do before PRO ships — it directly undercuts the activation model.

2. **CLI ships without Hardened Runtime (H-2).** `project.yml:225`
   `ENABLE_HARDENED_RUNTIME: NO` on `VitrineCLI` — the binary that verifies the license token
   can be `DYLD_INSERT_LIBRARIES`-injected / patched to bypass `CLIEntitlement.isProUnlocked()`.
   It is orthogonal to the font-staging `ENABLE_USER_SCRIPT_SANDBOXING: NO`; re-enable hardened
   runtime for the CLI.

3. **Remote image download follows redirects without re-validating the final host (M-3).**
   `Vitrine/Models/BackgroundImageStore.swift:101-121` validates the entry URL scheme but
   `URLSession.shared` auto-follows 30x to e.g. `http://169.254.169.254/…` (SSRF on the
   direct-download build, which carries the network entitlement). Add a redirect delegate that
   re-runs the private-host check. (Mitigated today by the sandbox + `NSImage` validation.)

4. **SSRF allow/deny list gaps (M-1).** `Vitrine/WebRendering/WebSnapshotConfig.swift:592-622`
   misses `100.64.0.0/10` (Tailscale/CGNAT), `0.0.0.0/8`, and `240/4`; DNS-rebinding is an
   unmitigated residual (acknowledge in CS-043 — user consent is the real mitigation).

5. **Path-component guard incomplete (M-2).** `BackgroundImageStore.swift:159` blocks `/`,
   `..`, `.` but not `\` or dot-prefixed names. Add `!name.contains("\\")` and
   `!name.hasPrefix(".")` for defense in depth.

6. **`LicenseVerifier.embedded` regenerates a random key each launch (L-1).**
   `LicenseKey.swift:48` — intentional placeholder, but add a CI test asserting the embedded
   public key is a fixed, non-random literal before the first PRO release (else a forgotten
   substitution silently locks out every paying user).

---

## P1 — Performance (render hot path)

The render core is shared by the editor preview, exports, recents thumbnails, social cards,
CLI batch, and multi-viewport — so these multiply across every surface.

1. **`HighlightManager` does no memoization — the single biggest win.**
   - Every color accessor (`backgroundColor`/`gutterForegroundColor`×2-3/`lineHighlightColor`/
     `metadataBadgeColor`) calls `highlightr.setTheme(to:)`, which reparses the theme CSS. One
     `SnapshotCanvas.body` does **~6 redundant CSS reparses**; in the live editor that is per
     keystroke. `Vitrine/Editor/HighlightManager.swift:50,129`. Cache `(themeID) →
     (background, isDark)` and only `setTheme` on id change.
   - No tokenization cache: `attributedString(...)` re-tokenizes the whole document on every
     `body` even when only padding/background changed (`HighlightManager.swift:33`,
     `SnapshotCanvas.swift:230`). Add an LRU keyed on
     `(code,language,themeID,font,size,ligatures)`.

2. **`normalized()` does a full-bitmap copy even on the default sRGB path.**
   `Vitrine/Export/ExportManager.swift:47,60-83` allocates+draws+copies the entire output
   bitmap every render; for sRGB it is a no-op that still costs ~27 MB at 3600×1890. Short-
   circuit when `cgImage.colorSpace` already matches `profile`.

3. **Whole pipeline runs synchronously on `@MainActor`.** `ExportManager.renderCGImage`
   (highlight + `ImageRenderer` + `normalized`) blocks the UI for every export; `RecentsStore
   .add` renders+encodes a thumbnail inline on capture. Hoist `normalized()`/`pngData()` (they
   operate on a finished `CGImage`) and the recents thumbnail onto a background `Task`.

4. **Inline logo `Data` in the Equatable render config.** `Watermark.logoImageData: Data` on
   `SnapshotConfig` (Equatable) makes SwiftUI's diff and every `config` value-copy byte-compare/
   deep-copy the logo. `Vitrine/Models/SnapshotConfig.swift`. Give `Watermark` a custom `==`
   comparing a cheap logo identity (hash/`ImageReference`), or store the reference and resolve
   bytes only at the `WatermarkBadge` draw seam.

5. **`WatermarkBadge` re-decodes the logo `Data → NSImage` every `body`.**
   `Vitrine/Canvas/WatermarkBadge.swift:39`. Cache the decoded `NSImage` in `BrandKitStore`
   beside `cachedLogoData`.

6. **Multi-viewport batch retains ~5-6 full-res captures + the board for the window's
   lifetime** (`WebSnapshotModel.results`/`boardAsset`, `WebSnapshotWindowController.swift`),
   and the filmstrip hands SwiftUI full-res bitmaps to rescale to 92×58 every layout. Clear
   the model on `windowWillClose`; store a downsampled thumbnail per `CapturedViewport`.

---

## P1 — UX / HIG (the new PRO surfaces)

1. **Multi-size export gives no success feedback and strands partial failures.**
   `Vitrine/Export/MultiSizeExportView.swift:121-127` — `dismiss()`s silently on success
   (every other export shows a `CaptureHUDController` confirmation) and discards the
   `(written, failed)` count on partial failure. Present "Exported N images" + reveal the
   folder; report "Wrote N, M failed".

2. **Accent color is a one-way trap.** `Vitrine/Settings/SettingsPanes.swift:896-899` coerces
   `nil → .white` in the getter and always writes a concrete color, so the model's "no accent
   (use legible default)" state can never be restored, and the swatch is white-on-white in
   Light mode. Add a "Default"/reset affordance that sets `accent = nil`.

3. **Logo import failure is silent.** `SettingsPanes.swift:846` ignores `importLogo`'s `Bool`;
   surface an inline error like the editor's file-load alert.

4. **Paywall polish:** "Restore Purchases"/"Not now" are `.plain` (read as labels, not
   controls); no Esc/Return shortcuts; `ProBadge` overlaps the 30×30 toolbar icon and double-
   announces in VoiceOver. `Vitrine/Pro/ProGate.swift:43,90-95,160-163`,
   `EditorView.swift:347-350` — use `.link`/`.bordered`, add `.cancelAction`/`.defaultAction`,
   `ProBadge().accessibilityHidden(true)` on the toolbar.

5. **Token-system consistency:** the upsell + both sheets are hand-built with raw
   `VStack`/`Text(.system(size:))` instead of `TokenGroup`/`TokenRow`; placement `Picker` is
   hard-coded `width: 160` (truncates under localization); badge/chips use `Color.white` instead
   of `VitrineTokens.Accent.contrast`.

---

## P2 — Architecture, refactors, dead code, docs

1. **`AppSettings` is the clearest god-object** (≈550 lines, 25 `@Published`). The 10-property
   web-capture cluster (`AppSettings.swift:122-201`) extracts cleanly into a `WebCaptureSettings`
   sub-store the way `BrandKitStore`/`PresetStore` already did. **`SettingsPanes.swift` is
   ~1,900 lines** and **`EditorView.swift` ~1,015** — split per-pane / extract subviews.

2. **Duplicated WKWebView load coordinators.** `URLRenderer.LoadCoordinator`
   (`URLRenderer.swift:440-512`) and `WebSnapshotView.NavigationCoordinator`
   (`WebSnapshotView.swift:360-477`) share the same continuation/timeout/`resume` machinery
   (~60 lines). Extract a shared base.

3. **Leaky abstraction:** `Entitlements.purchase()/restorePurchases()` downcast
   `provider as? StoreKitProvider` (`Entitlements.swift:52-67`). Add `purchase()/restore()` to
   `EntitlementProvider` (no-op default) to remove the cast and make it fake-testable.

4. **Dead/duplicative code:** `URLRenderer.configured(from:)` (`URLRenderer.swift:146`) is never
   used by the multi-viewport path, which constructs `URLRenderer` directly and drops
   `safetyCaps`/`dataStoreMode` — make it the canonical builder or remove it.
   `ResponsiveBoardComposer.swift:94-99` board gradient uses unnamed float literals — extract a
   named constant.

5. **`@MainActor` static property without annotation:** `WebSnapshotView.cachedRemoteBlockList`
   (`WebSnapshotView.swift:253`) — add `@MainActor` to the stored property to future-proof under
   strict concurrency.

6. **Documentation gaps (explicit ask).** `docs/ARCHITECTURE.md` is materially stale: its module
   map omits ~9 folders (`Pro/`, `WebRendering/`, `SocialCards/`, `DesignSystem/`, `State/`,
   `Recents/`, `Updates/`, `Help/`, `Rendering/`), lists the removed `Settings` SPM package, and
   has **zero** coverage of the PRO subsystem or web multi-viewport. The full PRO specs live only
   in the git-ignored `docs/ROADMAP.md`. → Addressed by the new `docs/PRO.md` and an
   `ARCHITECTURE.md` refresh. README has no PRO mention (defer until PRO commits).

7. **Modernization:** migrate the 11 `ObservableObject` stores to the `@Observable` macro
   (macOS 14 target) for property-level view invalidation — pilot on the small, well-tested
   `Entitlements`/`BrandKitStore`. Do **not** adopt SwiftData (the flat JSON-in-`UserDefaults` +
   versioned-migration + defensive-decode model is correct for these shapes).

8. **Dependencies are current** (Highlightr 2.3.0, KeyboardShortcuts 2.4.0, Sparkle 2.9.3 —
   all pinned at or ahead of latest). One watch-item: **Highlightr's upstream is dormant**;
   track `HighlighterSwift` / Tree-sitter as the eventual highlighter migration. No urgency.

---

## What is genuinely strong (do not "fix")

- The render-core / edges boundary holds byte-for-byte: `WatermarkOverlay` is a true no-op when
  nil; the watermark never touches the stored config, persistence, presets, or the golden suite.
- Swift-6 concurrency is **clean** — no `@unchecked Sendable`, `nonisolated(unsafe)`, detached
  tasks, deprecated APIs, or data races in the new code.
- The provider/store injection pattern, the CS-053 per-window volatile sessions, the offline
  Ed25519 verify-before-store, and the `debugUnlockProviderIsCompiledOutOfRelease` source-scan
  guardrail are all well-built and well-tested.
- Inline doc-comment quality is excellent throughout the new `Pro/` files; the gaps are at the
  project/architecture-doc level only.
