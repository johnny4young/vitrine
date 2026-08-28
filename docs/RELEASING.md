# Releasing Vitrine

> **First time shipping?** Opening the Apple Developer account, generating the signing
> certificate and notary/Sparkle keys, picking the names, and creating the GitHub
> Pages/Homebrew-tap infra is a one-time **manual** job, kept in a maintainer-only local
> runbook. This file assumes those credentials already exist and covers running the
> pipeline.

Vitrine's canonical distribution channels are a Developer ID-signed, notarized DMG
attached to a GitHub release and the Homebrew cask that consumes it. The Mac App Store
is an optional secondary GUI-only channel and never blocks a direct-channel release. The
pipeline degrades gracefully: without signing
secrets it still produces an **unsigned** DMG for local development — but that
unsigned build is **never production-ready** (Gatekeeper rejects it). Tag-triggered
release candidates do **not** degrade: missing signing, notarization, Sparkle, or PRO
credentials fail before packaging. See
[Signing, notarization & Gatekeeper](#signing-notarization--gatekeeper).

## One command, locally

```bash
VERSION=0.1.0 ./scripts/build-dmg.sh
# → dist/Vitrine-0.1.0.dmg  (+ prints the SHA-256)
```

## Tagged release candidate (CI)

Pushing a tag triggers the private candidate half of `.github/workflows/release.yml`:

```bash
VERSION=0.1.0
git switch main
git pull --ff-only
git tag -a "v${VERSION}" -m "Vitrine v${VERSION}"
git push origin "v${VERSION}"
```

Release tags must be annotated and use stable SemVer with a `v` prefix. The tag run
rejects lightweight, prerelease, or malformed tags, executes the release gates, requires
every production signing/notarization/update/activation secret, and builds the signed,
notarized DMG. It then generates the checksum, SBOM, signed appcast, Homebrew metadata,
and curated changelog notes, attests the DMG, and uploads them together as a private
`release-candidate-vX.Y.Z` Actions artifact retained for 30 days.

The tag run **does not** create a GitHub release, change Homebrew, deploy the production
appcast, or refresh the website. A fresh runner downloads that candidate, verifies its
manifest and SHA-256, and runs `scripts/qa-release.sh`; the run is successful only after
that independent check passes.

## Promote a vetted candidate

1. Download the candidate named in the successful tag run summary:

   ```bash
   TAG=v1.2.0
   CANDIDATE_RUN_ID=123456789
   rm -rf release-candidate
   gh run download "${CANDIDATE_RUN_ID}" \
     --name "release-candidate-${TAG}" \
     --dir release-candidate
   (cd release-candidate && shasum -a 256 -c ./*.dmg.sha256)
   ```

2. Copy that exact DMG and `scripts/qa-release.sh` to clean Sequoia and Tahoe Macs.
   Complete the automated and manual checklist below, including live PRO activation,
   offline relaunch, deactivation, universal executable inspection, and the supported
   UI journeys. Record the candidate run ID, tag, DMG SHA-256, machine architecture,
   and exact macOS versions; never record credentials.
3. Only after both clean-Mac checks pass, dispatch the same workflow manually:

   ```bash
   SHA256="$(shasum -a 256 release-candidate/Vitrine-1.2.0.dmg | awk '{print $1}')"
   gh workflow run release.yml \
     -f tag="${TAG}" \
     -f candidate_run_id="${CANDIDATE_RUN_ID}" \
     -f expected_sha256="${SHA256}" \
     -f qa_confirmation=CLEAN-MAC-QA-PASSED
   ```

Promotion fails closed unless the referenced run belongs to this repository and release
workflow, was triggered by a tag push, completed successfully at the annotated tag's
exact commit, and contains a DMG matching the approved SHA-256. It re-downloads and
re-runs release QA **before** creating the immutable GitHub release. A third runner then
downloads the public DMG and proves it is still the approved candidate before Homebrew,
the production Sparkle feed, or the marketing site changes.

GitHub immutable releases are enabled: after publication, the tag, release notes, and
attached artifacts cannot be altered or replaced. If a published artifact is wrong,
fix the source and publish a new patch version instead of rewriting release history.

## Continuous integration

CI is a release gate, not just a compile check.

- **`.github/workflows/ci.yml`** runs on every push to `main` and every pull
  request. Its macOS gates are an explicit two-row runtime matrix:
  `macos-15` (Sequoia) and `macos-26` (Tahoe). Before building, each row records
  the exact image, Xcode, and Swift versions into the job summary, so a green or
  red result is always tied to a known environment. CI validates every workflow's
  YAML, then runs `make lint`, `make build`, `make build-release`,
  `make build-ui-tests`, and `make test-coverage`. The Release lane compiles both arm64
  and x86_64 with optimization on every supported runner, so optimizer-only failures are
  caught before packaging. The Swift Package Manager download cache is restored between
  runs (keyed on `project.yml`,
  the dependency source of truth) to cut build time without risking a stale build.
  A parallel **`UI tests` job** executes the full XCUITest suite (`make test-ui`)
  plus the strict visual evidence tour (`make test-visual`) on both OS rows and the
  same triggers — see *Running the UI tests* below.
- **`.xcresult` on failure.** The build and test steps pass `RESULT_BUNDLE=…` to
  `make`, and on any failure CI uploads the resulting `.xcresult` bundles (plus the
  golden-diff and launch-gallery artifacts) so a failure can be triaged offline
  without re-running CI.
- **Weekly drift watch.** A scheduled run (Mondays 08:00 UTC, also available via
  *Run workflow*) re-runs the full Sequoia + Tahoe matrix. GitHub rolls both
  explicit images and their bundled Xcode/SDKs on its own cadence, which can break
  the build with no code change; the scheduled run surfaces that drift on a
  predictable day instead of on the next unrelated PR.
- **Pinned release tooling and dependency inventory.** CI downloads XcodeGen's official
  universal release archive, verifies its pinned SHA-256 digest, and installs it into a
  runner-local prefix instead of depending on Homebrew's moving formula. A weekly workflow
  compares both the XcodeGen and Sparkle versions and checksums with GitHub's published
  release metadata. Each GitHub release includes a versioned SPDX JSON SBOM alongside the
  DMG and checksum.
- **The release workflow refuses to publish an unvetted build.** `release.yml` runs
  `verify`, builds a private candidate, re-downloads it onto an independent QA runner,
  and stops. Public promotion is a separate manual dispatch that pins the successful
  candidate run, tag commit, operator-confirmed clean-Mac checklist, and SHA-256. The
  published bytes pass QA again before downstream distribution changes.

### Supported macOS matrix

`project.yml` remains the source of truth and sets the public deployment target to
macOS 15.0 Sequoia. Every app-owned target uses that same floor, and the Homebrew cask
declares `:sequoia` so unsupported installations fail before launch. Active runtime
certification covers:

| Runtime | GitHub label | Required gates |
| --- | --- | --- |
| macOS 15 Sequoia | `macos-15` | Build, unit/integration, performance, golden rendering, full UI suite, strict visual tour |
| macOS 26 Tahoe | `macos-26` | Build, unit/integration, performance, golden rendering, full UI suite, strict visual tour |

Both are standard arm64 GitHub-hosted labels. `setup-xcode` selects the newest stable
Xcode installed on each image, and the workflow logs the resolved versions instead of
assuming they match. `fail-fast: false` ensures a failure on one OS never cancels the
evidence from the other. Artifact names include `sequoia-15` or `tahoe-26`, preventing
parallel matrix uploads from colliding.

The matrix also proves capability-specific UI rather than pretending both systems ship
identical codecs. ImageIO exposes PNG, PDF, and HEIC writers on both rows; AVIF is shown
and restored only when `CGImageDestinationCopyTypeIdentifiers()` reports its writer
(Tahoe and newer). Sequoia must omit AVIF from interactive pickers and return a typed CLI
error for an explicit AVIF request instead of surfacing a late generic render failure.

An unreleased future macOS major is not silently claimed as supported. Add its explicit
runner label to both matrices, obtain a green build/UI/visual run, and update this table
before calling that runtime certified.

The separate **Xcode 27 preview** workflow is a weekly/manual, non-required early-warning
lane on GitHub's `xcode-27` preview image. That image uses a macOS 26 host and the preview
Xcode/SDK; the lane runs lint, a Debug build, and unit tests only. It does not run on pull
requests, does not publish, and is not a claim of macOS 27 runtime support. Promote it to
the required compatibility matrix only after GitHub provides the corresponding macOS
runner as GA and the full runtime, UI, visual, performance, and clean-Mac evidence exists.

### Unit-test lanes

`make test` is the default local feedback lane. It runs the complete Swift Testing
suite with coverage explicitly disabled, avoiding an Xcode 26 failure mode where the
test process finishes successfully but `xcodebuild` stalls while finalizing coverage.
This changes instrumentation only; it does not select or skip tests.

`make test-coverage` runs the same complete suite with coverage explicitly enabled.
The lane always writes an `.xcresult` and passes its `xccov --json` report and raw line
archive through `scripts/check-coverage.py`; an absent, empty, or malformed report fails
the gate rather than becoming a best-effort warning. CI selects the committed baseline
for its Sequoia or Tahoe row, retains failure bundles, and publishes per-target `xccov`
output in the job summary. The weighted coverage across `Vitrine.app`, `vitrine-cli`,
and `VitrineMenuBarHelper` may not fall more than one percentage point below the
pre-hardening baseline for that OS.

The same guard requires at least 80% of changed executable lines in critical logic to be
covered. Its unit-coverage scope is `Models`, `CLI`, `Pro`, `Terminal`, `Rendering`, and
the explicit non-visual policy/renderer files in `WebRendering`. SwiftUI/AppKit views and
window controllers are deliberately outside that calculation: XCUITest and the strict
visual tour protect those surfaces. Baselines live under
`scripts/coverage-baselines/`; they are GitHub-hosted runner baselines because WebKit
subprocess availability can change which qualification tests execute in a restricted
local environment. Update one only from a complete passing hosted run on the named
OS/toolchain, record its exact covered/executable counts, and pin the source revision.
For a local comparison, override `COVERAGE_BASELINE` with a same-environment baseline;
do not weaken the committed hosted threshold to accommodate a local skip. Run
`make coverage-check` for the parser's fast self-test. Keep the lanes separate: local
feedback must not depend on coverage finalization, and CI coverage must not depend
implicitly on the Xcode scheme default.

### Dynamic memory evidence

Run `make memory-smoke` before a release candidate and after changes to window,
renderer, observer, or asynchronous-task lifecycles. It runs the normal headless Debug
build, reusing Xcode's already-resolved exact package checkouts, then launches a selected
isolated journey under Apple's `leaks --atExit`. The four journeys cover repeated editor
snapshot rasterization; deterministic foreground-image import, decode, replacement, and
teardown; twenty additional editor window open/render/close cycles; and ten distinct real
local-HTML WebKit session captures. The image and WebKit journeys reject duplicate output,
while window churn requires a capture from the exact newly-opened editor. The image journey also removes its synthetic
temporary store before reporting completion. The raw journey-named memgraph, full stack
report, launch log, and a machine-readable summary are retained below
`build/memory-smoke/<timestamp>/`.

```bash
make memory-smoke

# Exercise distinct foreground-image imports, decodes, replacements, and teardown.
make memory-smoke MEMORY_JOURNEY=image-import-cycle

# Exercise one additional editor at a time through normal window teardown.
make memory-smoke MEMORY_JOURNEY=window-churn

# Exercise newly-created non-persistent WebKit sessions with local HTML only.
make memory-smoke MEMORY_JOURNEY=web-snapshot-cycle

# Run editor, image, window, and WebKit journeys sequentially against one build.
make memory-smoke-all

# Compare counts and footprints only with an earlier run from the exact same clean
# commit, OS, architecture, Xcode, and journey. The report marks any provenance drift
# instead of pretending the evidence is comparable.
make memory-smoke \
  MEMORY_JOURNEY=image-import-cycle \
  MEMORY_BASELINE=build/memory-smoke/<earlier-run>/report.json
```

This is deliberately an **evidence lane, not a zero-leak CI gate**. At-exit analysis
cannot detect every reachable retain cycle or prove a stable long-running footprint;
Apple frameworks can own reported roots; and a Vitrine frame only proves that the app
was on an allocation path, not that it owns the leaked object. Snapshot rasterization
also contributes to the peak footprint. Review the root stacks in `leaks.txt` and the
memgraph before classifying a regression. The command fails when the build, journey,
capture, or report is invalid, but it does not silently allowlist framework roots or
turn their mere presence into an app failure. Keep all generated evidence local and
untracked. Compare only repeated, same-provenance root or footprint growth; do not change
ownership based only on allocation-path frames. The image journey deliberately uses local
bounded fixtures; it does not replace the unit coverage for oversized/corrupt inputs and
does not simulate an external item provider that never calls back. The local-HTML WebKit
journey does not qualify public network capture, and the window journey does not cover
every auxiliary window type.

### Running the UI tests

**The full UI suite (`make test-ui`) runs in CI on every PR and push to `main`**,
as the dedicated `UI tests` job in `ci.yml`, alongside the compile-only
`make build-ui-tests` step that also remains in the build job and the release gate.
Both `macos-15` Sequoia and `macos-26` Tahoe must finish; the matrix does not cancel
one runtime merely because the other failed.

Driving the menu-bar app through XCUIAutomation requires the macOS
"automation permission" — the interactive UI-automation consent that the first
local `make test-ui` prompts for; grant it once. GitHub-hosted macOS runners need
no prompt: the images are provisioned for headless UI automation
(`DevToolsSecurity --enable`, `automationmodetool
enable-automationmode-without-authentication`, SIP disabled — see
`images/macos/scripts/build/configure-machine.sh` in `actions/runner-images`),
verified empirically on the `macos-15-arm64` image (20260527.0100.1): the suite
executes end to end. The explicit `macos-26` row applies the same gate and captures
the same diagnostics on Tahoe. One sharp edge from the Sequoia verification:
`automationmodetool`
*reports* "Automation Mode is disabled" on that image even though automation
works, so the CI job records the authorization state as a diagnostic instead of
gating on it. When the job fails because the XCUITest session could not
initialize — a runner-image regression, which has happened before
(actions/runner-images#7621, #8546) — a dedicated step annotates the run as an
infrastructure failure rather than a product bug.

For local runs, keep Vitrine/XCTest frontmost while the suite is active. XCUITest
can report unrelated windows as "interrupting elements" (Slack, browsers, or an
IDE on another display) even when the app itself is healthy. If a local run fails
only with interrupting-window diagnostics, close or hide those windows and rerun
the focused test before treating it as a product regression.

Both `make test-ui` and `make test-visual` now inspect the process table before
deleting old result bundles or launching Xcode. An active macOS UI-test runner —
including a stale Vitrine runner or a runner from another checkout — fails the
preflight with its PID and executable name. Concurrent runners can steal focus and
TestManager ownership, so their failures are not trustworthy product evidence.
Finish or stop the existing suite explicitly, then rerun; the preflight never
terminates another process automatically. `make ui-test-preflight-check` exercises
the parser with deterministic fixtures and is part of `make lint`.

**The display-geometry-sensitive tests run on CI too.** Four tests
(`testEditorExposesMakeDefaultToolbarAction`,
`testEditorExposesFormatCodeToolbarAction`,
`testEditorKeyboardCanReachToolbarAndInspector`, and
`testEditorWindowRecoversFromOffScreenFrame`) assert toolbar hittability and
off-screen-recovery geometry, which used to fail on the runner's small 1024x768
virtual display: the editor's 1180-point default window overhung the screen
edges, leaving its trailing toolbar actions unhittable. The product now sizes
brand-new and recovered editor windows to fit the screen they open on
(`WindowFrameSolver`), so the suite passes on that display, and the tests
`XCTSkipUnless` (with an explanatory message) only when no display can hold the
editor's minimum supported window — smaller than anything CI uses. On a
hittability failure the tests attach the screen/window/element geometry plus the
accessibility hierarchy to the `.xcresult`. Should a future runner image shrink
the display again, individual tests can still be excluded with
`make test-ui TEST_UI_SKIP="<test> <test>"` — if you reintroduce that in `ci.yml`,
annotate every skipped test on every run so the skip stays visible.

Hosted virtualization can expose different screen coordinate spaces to the XCTest
process and the launched app. Product windows therefore size and clamp themselves only
against AppKit's own `NSScreen.visibleFrame`; transferring XCTest coordinates into the
app would mix incompatible spaces. Welcome accepts a compact width, while Recents uses
an adaptive in-content action bar so every action remains present when AppKit reports a
narrow logical display. Failure attachments include both AppKit and XCUIAutomation
geometry for diagnosis. Targeted UI selectors also choose a hittable match when AppKit
exposes one identifier on both a wrapper and its nested control, which keeps the same
assertions valid across Sequoia and Tahoe accessibility trees.

The release gate (`release.yml`) still only *compiles* the UI tests: every commit
on `main` has already had the full suite executed by `ci.yml`, and a UI-level
flake should not block an urgent tag. Run `make test-ui` locally before tagging if
the release includes UI changes that never went through a PR.

### Running the strict visual tour

`make test-visual` runs the 53-state `ScreenshotTourUITests` catalog separately from
the ordinary UI smoke suite. Every state is a required `.xcresult` attachment: a
missing state, invalid or duplicate PNG, empty capture frame, source/manifest drift,
or a capture attempted while another application is frontmost fails the command.
The validator then exports stable filenames plus a dimension/hash manifest under
`build/screenshot-tour/`; the raw bundle remains at
`build/screenshot-tour.xcresult` for offline diagnostics.

CI runs this gate on every pull request and push to `main` and uploads the friendly
evidence even on success. For a local run, keep Vitrine frontmost and avoid launching
other applications until the tour finishes. This is intentional: visual evidence
that contains an interrupting browser, terminal, or IDE must fail rather than be
mistaken for a valid Vitrine screenshot.

## Signing, notarization & Gatekeeper

Outside the Mac App Store, modern macOS expects a direct download to be **Developer
ID-signed and notarized**, or Gatekeeper blocks first launch. `scripts/build-dmg.sh`
does all of it and degrades gracefully: with no signing identity it still produces an
**unsigned, ad-hoc DMG** for local development. **That unsigned path is for
development only and is never production-ready** — the script prints exactly that and
Gatekeeper rejects the artifact.

What the script does for a signed build:

Before either the signed or unsigned path can create a DMG, the script builds for a
generic macOS destination with `ONLY_ACTIVE_ARCH=NO` and `ARCHS="arm64 x86_64"`. It
then enumerates **every executable Mach-O payload** in the app with `lipo -archs` and requires both
architectures. This includes the embedded CLI, menu-bar helper, frameworks, and XPC
services; checking only the outer executable would allow a partially thin app to reach
Intel users. A missing architecture stops before signing or notarization.

1. **Signs** the already-verified universal app with the Developer ID Application identity.
2. **Keeps the hardened runtime on** (`ENABLE_HARDENED_RUNTIME=YES`, set in
   `project.yml` and re-asserted on the signed build) — required for notarization.
3. **Requests secure code-signing timestamps** (`OTHER_CODE_SIGN_FLAGS=--timestamp`)
   for the signed Xcode build. Apple notarization requires a secure timestamp; a
   headless build that signs with `--timestamp=none` can pass local `codesign`
   verification and still be rejected by the notary service.
4. **Repairs distribution-only signing gaps** from the direct build path: disables
   Xcode's base entitlement injection (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`) so
   `com.apple.security.get-task-allow` cannot leak into the app, explicitly signs the
   embedded CLI and the paint-only menu-bar helper (preserving the helper's sandbox
   inheritance entitlements), then re-signs Sparkle's nested helpers (`Installer.xpc`,
   `Downloader.xpc`,
   `Autoupdate`, and `Updater.app`) with Developer ID + timestamp before re-sealing
   the outer app. This mirrors the work Xcode Archive/Export normally does; do not
   use `--deep` for this Sparkle repair because the helpers have different
   entitlement requirements.
5. **Verifies** the signature with `codesign --verify --deep --strict --verbose=2`.
6. **Notarizes** with `notarytool` (App Store Connect API key **or** Apple ID
   credentials — see below), then **staples** the ticket to the app, signs the DMG,
   and staples the DMG too so first launch validates offline.
7. **Assesses Gatekeeper** with `spctl -a -vv` on the app and the DMG.

If Apple returns anything other than `Accepted`, the script now fetches and prints the
structured `notarytool log` before it tries to staple. That log is the source of truth
for signing defects; a stapler-only `Record not found` error just means there was no
accepted ticket to attach.

### Credentials (repository secrets)

Local `build-dmg.sh` runs may omit credentials and produce an explicitly unsigned
development artifact. A tag candidate is different: the workflow requires Developer ID
signing, PRO and Sparkle keys, and one complete notarization credential style before it
builds. The App Store Connect API key is preferred for CI (no app-specific password) and
wins when both styles are configured.

| Secret | Purpose |
| --- | --- |
| `MACOS_CODE_SIGN_IDENTITY` | Developer ID Application identity name (enables signing) |
| `MACOS_CERTIFICATE_P12` | Base64-encoded `.p12` export of the Developer ID cert + key |
| `MACOS_CERTIFICATE_PASSWORD` | Export password for that `.p12` |
| `MACOS_NOTARY_TEAM_ID` | Developer Team ID (also used as `DEVELOPMENT_TEAM`) |

App Store Connect API key (preferred for CI):

| Secret | Purpose |
| --- | --- |
| `MACOS_NOTARY_KEY_P8` | Base64-encoded `.p8` private key |
| `MACOS_NOTARY_KEY_ID` | API Key ID |
| `MACOS_NOTARY_KEY_ISSUER_ID` | Issuer ID for the key |

Apple ID style (fallback):

| Secret | Purpose |
| --- | --- |
| `MACOS_NOTARY_APPLE_ID` | Apple ID for `notarytool` |
| `MACOS_NOTARY_PASSWORD` | App-specific password |
| `MACOS_NOTARY_TEAM_ID` | Developer Team ID |

PRO direct-download activation:

| Secret | Purpose |
| --- | --- |
| `VITRINE_LICENSE_SIGNING_KEY` | Base64 of the 32-byte Ed25519 **private** signing key. Injected into the DMG's `VitrineLicenseSigningKey` Info.plist value (via `project.yml`) so the released build can mint + sign activation tokens. Unset → the build can't mint a token and PRO stays inert (a fork or PR build never gets it). The matching **public** key is committed in `LicenseVerifier.embedded`. See [`ACTIVATION.md`](ACTIVATION.md). |

Set it once from the key you generated for the keypair (keep the private half in your
login Keychain, never in the repo):

```bash
gh secret set VITRINE_LICENSE_SIGNING_KEY --repo johnny4young/vitrine \
  --body "$(security find-generic-password -s vitrine-license-key -w)"
```

The release workflow imports `MACOS_CERTIFICATE_P12` into a temporary runner keychain
before building (the **Import Developer ID certificate** step), and stages
`MACOS_NOTARY_KEY_P8` to a file (the **Stage App Store Connect API key** step). A missing
certificate, signing identity, Sparkle signer, PRO signer, Team ID, or complete notary
credential set makes the tag run fail; an unsigned candidate can never become promotable.
`TAP_DEPLOY_KEY`, `CLOUDFLARE_API_TOKEN`, and `CLOUDFLARE_ACCOUNT_ID` are checked before
manual promotion creates the immutable release, preventing a known-missing distribution
credential from creating immediate channel drift.

### Local dry run (unsigned)

```bash
VERSION=0.1.0 ./scripts/build-dmg.sh
# → dist/Vitrine-0.1.0.dmg  (UNSIGNED — development only, not production-ready)
```

### Local dry run (signed, once you hold a Developer ID)

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MACOS_NOTARY_KEY_P8="$HOME/keys/AuthKey_XXXX.p8" \
MACOS_NOTARY_KEY_ID="XXXXXXXXXX" \
MACOS_NOTARY_KEY_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
VERSION=0.1.0 ./scripts/build-dmg.sh
```

### Verifying a downloaded artifact

The script runs these automatically; you can re-run them on any built artifact:

```bash
codesign --verify --deep --strict --verbose=2 dist/Vitrine.app
spctl -a -vv dist/Vitrine-0.1.0.dmg   # "accepted … Notarized Developer ID"
xcrun stapler validate Vitrine.app
```

## Homebrew cask

The goal is a reliable `brew install --cask johnny4young/tap/vitrine`.

There are two copies of the cask, and the distinction matters:

- **`packaging/Casks/vitrine.rb`** (this repo) is the **source template**. It is the
  single place to evolve the stanzas (name, desc, homepage, URL pattern, livecheck,
  `depends_on`, the `app` artifact, the `binary` stanza that puts the embedded
  `vitrine` CLI on PATH, and the `zap` cleanup). It carries a
  **placeholder `sha256`** (all zeros) so it stays valid for `brew style`/`brew audit`
  without claiming to match any real DMG.

  > The `binary` stanza points at `Contents/MacOS/vitrine-cli` (named so it
  > cannot collide with the `Vitrine` app executable on case-insensitive APFS;
  > `target:` surfaces it on PATH as `vitrine`). The file exists in DMGs from
  > **v0.5.0** onward (embedded by the app target's post-build script and
  > signed by `build-dmg.sh`). Do not sync that stanza into the tap while it
  > still serves an older DMG — the install would fail on the missing file.
- **`Casks/vitrine.rb`** in the tap (`johnny4young/homebrew-tap`) is what users install.
  It is this template with `version` bumped and `sha256` set to the **published DMG's**
  checksum.

### What the release workflow stores for you

`release.yml`'s **Compute and store DMG SHA-256** step runs right after the DMG is
built. It:

- computes the DMG SHA-256 and **prints** it to the run's job summary (visible from the
  Actions run page, no download needed);
- **stores** it as a `Vitrine-<version>.dmg.sha256` sidecar, attached to the GitHub
  release alongside the DMG; the sidecar names only the DMG basename, so downloading
  both files into one directory and running `shasum -a 256 -c *.dmg.sha256` works
  without recreating the workflow's `dist/` path; and
- writes a ready-to-paste `vitrine-cask-update.txt` (the exact `version "…"` and
  `sha256 "…"` lines), also attached to the release.

So the checksum is never hand-copied off a terminal: it lives on the release.

### Updating the cask in the tap — automated

`release.yml`'s **Update the Homebrew tap cask** step runs only after the public
release has been downloaded on a fresh runner, matched to the approved candidate
SHA-256, and passed release QA again. It regenerates the cask from this repo's template
(header comment stripped, `version`/`sha256` substituted from the vetted DMG) and pushes
it straight to `johnny4young/homebrew-tap`. It authenticates with the
`TAP_DEPLOY_KEY` repo secret — a **write-enabled deploy key on the tap** (the
default `GITHUB_TOKEN` cannot reach other repositories). To rotate it:

```bash
ssh-keygen -t ed25519 -C "vitrine-release-tap-updater" -f tap_deploy_key -N ""
gh api -X POST repos/johnny4young/homebrew-tap/keys \
  -f title="vitrine release tap updater" -f key="$(cat tap_deploy_key.pub)" -F read_only=false
gh secret set TAP_DEPLOY_KEY --repo johnny4young/vitrine < tap_deploy_key
rm tap_deploy_key tap_deploy_key.pub
```

Promotion checks this secret before creating the immutable GitHub release. Missing
credentials fail closed; do not bypass the check to publish a knowingly inconsistent
release.

### Repairing the cask in the tap (incident fallback)

If the authenticated tap push fails unexpectedly after public release QA, open a PR against
`johnny4young/homebrew-tap`:

1. In the tap's `Casks/vitrine.rb`, paste the two lines from the release's
   `vitrine-cask-update.txt` (or copy them from the run summary) — i.e. set `version`
   to the new release and `sha256` to the published DMG's checksum. Keep every other
   stanza in sync with this repo's `packaging/Casks/vitrine.rb`.
2. Audit it strictly **in the tap** (this is where audit runs — by cask name, not by
   path):

   ```bash
   brew audit --cask --strict johnny4young/tap/vitrine
   brew style johnny4young/tap/vitrine
   ```
3. Smoke-test install and uninstall on a clean, compatible Mac (one without the repo or
   DerivedData):

   ```bash
   brew install --cask johnny4young/tap/vitrine
   open -a Vitrine                       # menu-bar app launches, no Dock icon
   brew uninstall --cask johnny4young/tap/vitrine
   ```
4. Merge the tap PR. `brew install --cask johnny4young/tap/vitrine` now resolves to the
   new version.

### Livecheck

The cask configures `livecheck` against the GitHub releases page
(`strategy :github_latest`), since a stable release-URL pattern exists. That lets
`brew livecheck vitrine` and Homebrew's automation detect when a newer tag is published.

### Auditing the template locally

`brew audit`/`brew style` operate on a cask **name in a tap**, not a loose file path, so
to audit this repo's template before it reaches the tap, drop it into a throwaway local
tap first:

```bash
TAP="$(brew --repository)/Library/Taps/johnny4young/homebrew-vitrinedev"
mkdir -p "$TAP/Casks" && cp packaging/Casks/vitrine.rb "$TAP/Casks/"
brew style packaging/Casks/vitrine.rb
brew audit --cask --strict johnny4young/vitrinedev/vitrine   # offline: stanza checks
rm -rf "$TAP"
```

The offline audit checks the stanzas. An `--online` audit additionally downloads the
DMG, so it only passes once a real release with a matching checksum exists.

## Release notes (What's New)

Release notes are bundled in the app and surface as a version-aware "What's New"
window, so they ship offline with the binary. They live in the repo at
`Vitrine/Help/ReleaseNotes.swift`.

For each release, add a `ReleaseNote` entry to `ReleaseNotes.all`, **newest first**:

```swift
ReleaseNote(
    version: "0.2.0",                 // must match MARKETING_VERSION
    headline: "One-line summary",
    highlights: [
        "A short, user-facing sentence per notable change.",
    ])
```

The `version` string must match the `MARKETING_VERSION` you bump in `project.yml`.
What's New appears once when the bundled version is newer than the version the user
last saw, and never on a clean first run (onboarding owns that). Keep `docs/HELP.md`
in step if the change also affects in-app Help.

## Changelog (CHANGELOG.md)

`CHANGELOG.md` at the repo root is the full, developer-facing history, in
[Keep a Changelog](https://keepachangelog.com) form — the granular record behind the
curated in-app notes above. During development, add a bullet under `## [Unreleased]`
(categorized `Added` / `Changed` / `Fixed` / `Removed` / `Security`) whenever a notable
change lands.

At release time:

1. Rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD`, and add a fresh empty
   `## [Unreleased]` above it.
2. Update the link references at the bottom of the file (the `[Unreleased]` compare and a
   new `[x.y.z]` compare line).
3. Curate the top few entries into the new `ReleaseNote` (above).

`make changelog-check` asserts the newest `## [x.y.z]` equals `MARKETING_VERSION` and
that an `[Unreleased]` section still exists, and the `AppStoreReadinessTests` suite pins
the changelog's newest version to both `MARKETING_VERSION` and `ReleaseNotes.latest` — so
the three can never drift. The immutable body is extracted from that version's complete
section in `CHANGELOG.md` and copied into the GitHub Release before publishing. The
extraction fails closed when the section is missing or empty because GitHub immutable
release notes cannot be edited after publication.

## Auto-update (Sparkle)

The **direct-download** build updates itself with [Sparkle](https://sparkle-project.org):
it checks a signed EdDSA appcast and installs the next build without a manual reinstall.
The **Mac App Store** build excludes Sparkle entirely (the App Store owns its own update
mechanism, and a third-party updater is disallowed there) — see
[App Store build excludes Sparkle](#app-store-build-excludes-sparkle) below.

### How it is wired

- **Local binary framework.** `Sparkle` (2.x) is fetched and checksum-verified by
  `scripts/fetch-sparkle.sh` into `Vendor/Sparkle.framework`, then embedded by
  `project.yml` with `embed: true`. This avoids the SPM binary-artifact resolution
  hangs seen on cold GitHub-hosted runners while still shipping Sparkle's
  Installer/Downloader XPC services inside the DMG's app bundle.
- **Compilation gate.** Every Sparkle call site is behind `#if VITRINE_DIRECT_DOWNLOAD`.
  The normal build sets that flag (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `project.yml`),
  so the DMG includes Sparkle and a user-visible **Check for Updates…** command (App menu).
  `Vitrine/Updates/SoftwareUpdater.swift` owns the integration.
- **Feed + key in `Info.plist`.** `SUFeedURL` points at the signed appcast on GitHub Pages
  (`https://johnny4young.github.io/vitrine/appcast.xml`); `SUPublicEDKey` is the EdDSA public
  key Sparkle verifies every download against.
- **Direct-download entitlements.** The DMG signs with
  `Vitrine/Resources/Vitrine.DirectDownload.entitlements`, the minimal set **plus**
  `com.apple.security.network.client` (so Sparkle can download) and the two Sparkle XPC
  `mach-lookup` exceptions. `scripts/build-dmg.sh` selects this file via
  `CODE_SIGN_ENTITLEMENTS`. The default and App Store builds keep the minimal
  `Vitrine.entitlements` (no network, no Sparkle), so the local rendering "no network" posture in
  [`docs/PERMISSIONS.md`](PERMISSIONS.md) is unchanged.
- **Sandboxed installer service.** `Info.plist` sets
  `SUEnableInstallerLauncherService = YES`, which Sparkle requires for every sandboxed host.
  `Installer.xpc` remains inside `Sparkle.framework`; do not copy or rename it. The app already
  owns `com.apple.security.network.client`, so `SUEnableDownloaderService` stays disabled.
  `scripts/build-dmg.sh` rejects a packaged app unless the final Info.plist, embedded service,
  and expanded `-spks` / `-spki` mach-lookup entitlements agree.
- **No analytics.** Sparkle's optional system profiling is off (`SUEnableSystemProfiling`
  is `NO`, and no profiling delegate is installed), so an update check sends only the
  requests needed to fetch the appcast and the chosen download — no telemetry.

### Generating the EdDSA signing keys (once)

Generate the key pair with Sparkle's `generate_keys` tool. The **private** key is stored in
your login Keychain and **must never be committed**; the **public** key goes in `Info.plist`.

```bash
# From Sparkle's binary tools (download the Sparkle-<version>.tar.xz release):
./bin/generate_keys
# → prints the public key and stores the private key in the Keychain.
```

Then:

1. Paste the printed public key into `Vitrine/Resources/Info.plist` under `SUPublicEDKey`
   (replacing the `REPLACE_WITH_SPARKLE_EDDSA_PUBLIC_KEY` placeholder).
2. Export the private key for CI and store it as the `SPARKLE_EDDSA_PRIVATE_KEY`
   **repository secret** (the appcast step reads it; it never leaves the secret):

   ```bash
   ./bin/generate_keys -x sparkle_private_key.pem   # export the private key…
   gh secret set SPARKLE_EDDSA_PRIVATE_KEY < sparkle_private_key.pem
   rm sparkle_private_key.pem                        # …then delete the local copy.
   ```

Losing the private key means you can no longer sign updates the installed base will accept,
so back it up securely (e.g. a password manager), exactly like the Developer ID certificate.

### Appcast published with each release

`release.yml`'s **Generate signed Sparkle appcast** step runs while building the private
candidate. `SPARKLE_EDDSA_PRIVATE_KEY` is mandatory for tag runs; a candidate without a
signed update path is rejected rather than published in a degraded state. The step:

- signs the DMG with Sparkle's EdDSA tooling and runs `generate_appcast` over `dist/` to
  produce a signed `appcast.xml`, with each item's download URL pointing at the release's
  DMG asset;
- stores `appcast.xml` inside the candidate so its bytes are reviewed with the DMG;
- attaches that exact file during manual promotion; and
- deploys it to **GitHub Pages** only after the public DMG passes post-upload QA.

The marketing site is **not** on GitHub Pages. Its Astro source lives in [`site/`](../site/)
and deploys to **Cloudflare Pages** (project `vitrine-web`, canonical domain
<https://vitrineframe.app>) through `deploy-site.yml`. Every trigger validates the site,
but a push to `main` **never** changes production: `main` can contain unreleased copy while
`MARKETING_VERSION` still names the previous release, so version equality is not release
provenance. Production accepts only an explicit annotated tag whose checked-out commit,
marketing version, and stable published GitHub Release all agree. This lets ordinary and
release-preparation merges exercise the complete site without announcing an artifact that
users cannot download yet.

After public-artifact QA and downstream distribution, the release workflow passes the
promoted tag to the reusable deploy, which checks out that exact ref rather than mutable
`main`. That direct call is deliberate: a release created with `GITHUB_TOKEN` does not
emit another workflow run, and an independent release event would bypass the required
ordering. A manual recovery deployment must supply the same published stable tag. The
locked local Wrangler dependency consumes the `CLOUDFLARE_API_TOKEN` /
`CLOUDFLARE_ACCOUNT_ID` secrets; an eligible production deployment fails rather than
silently skipping when either credential is absent.

GitHub Pages serves only the appcast plus a redirect stub from the legacy
`johnny4young.github.io/vitrine/` URL to the custom domain. The Cloudflare Pages project is
created once with `cd site && npm exec -- wrangler pages project create vitrine-web
--production-branch=main`.

So a tag produces evidence, while an approved manual promotion ships the same DMG and
refreshes the feed the installed base updates from. Sparkle compares appcast entries to the
installed bundle's `CFBundleVersion`, so remember to bump `CURRENT_PROJECT_VERSION` (and
`MARKETING_VERSION`) in `project.yml` for every release, or Sparkle will not see the new
build as newer.

### Reaching hosts whose updater cannot install

Builds before the one that added `SUEnableInstallerLauncherService` to `Info.plist` cannot
install an update at all. They are sandboxed but never opted into Sparkle's Installer XPC
service, so Sparkle falls back to submitting a privileged installer job, the sandbox denies
it (`errAuthorizationDenied`), and the user gets *"An error occurred while launching the
installer."* every time.

Shipping the fix does not repair them: the updater doing the work is the broken one already
on disk. What those builds can still do is fetch the appcast and show an alert. So after
`generate_appcast` runs, `release.yml` calls
[`scripts/mark-informational-update.py`](../scripts/mark-informational-update.py), which adds

```xml
<sparkle:informationalUpdate><sparkle:belowVersion>34</sparkle:belowVersion></sparkle:informationalUpdate>
```

to every entry. Those hosts then get a **download link** instead of an install that is
guaranteed to fail; hosts at or above that build are unaffected and keep updating in place.

The bound is compared against the host's `CFBundleVersion`, so it is a **build number**, not
a marketing version. It records when the updater started working and must not be raised to
track the current release — lowering or removing it silently strands everyone still running
one of those builds. `make lint` runs the script's `--self-test`, and
`SoftwareUpdateChannelTests` asserts the release applies it *before* staging the appcast for
Pages (otherwise the feed the installed base polls is the unmarked copy).

Retire it only once the affected builds are gone from the installed base — the DMG download
counts on those releases are the evidence for that, not a guess.

### Testing an update from N to N+1

1. Install the currently published version *N* from its real DMG; do not substitute a
   local build for the updater users actually have.
2. Complete candidate QA and manually promote *N+1*. The promotion workflow publishes the
   vetted DMG, verifies its public bytes, then deploys the signed production appcast.
3. Immediately launch installed *N* and choose **Check for Updates…** — Sparkle should find *N+1*,
   verify its EdDSA signature against `SUPublicEDKey`, and offer **Install Update**.
4. Click **Install Update** and require the app to relaunch on *N+1* with no installer or
   authorization error. Detecting and downloading the update is not a pass: this checks the
   complete sandboxed Installer Launcher journey.

A download whose signature does not verify is rejected, which is the man-in-the-middle
protection. Record the installed source/candidate versions and the final relaunched version in
the QA log. This exact production-feed journey necessarily happens immediately after promotion:
version *N* cannot download an asset or appcast that is not yet public. Candidate QA therefore
proves signing, notarization, embedded Installer XPC, entitlements, and launch behavior before
publication; the real *N*→*N+1* feed/install check is the final distribution audit. If it fails,
stop announcements and channel expansion, diagnose from the retained candidate/public evidence,
and publish a corrective patch — never rewrite the immutable release.

### App Store build excludes Sparkle

The optional Mac App Store build removes `VITRINE_DIRECT_DOWNLOAD` from
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` and **strips the Sparkle framework** from the bundle
before archiving (see `.github/workflows/appstore.yml` and
[`docs/APP-STORE.md`](APP-STORE.md)). With the flag absent, `SoftwareUpdater.isSupported`
is `false`, the **Check for Updates…** command is not added to the menu, and no Sparkle code
runs. The App Store entitlements (`Vitrine.entitlements`) stay network-free, so that channel
keeps the documented "no network" posture.

## Visual review — the launch gallery

Vitrine ships with generated design-QA evidence: a launch gallery of representative
screenshots rendered by the app itself, committed under `Tests/Fixtures/Samples/`.
Before tagging:

1. If any visual change landed this cycle, re-run `make gallery` and review the
   `Tests/Fixtures/Samples/` diff (the regenerated PNGs + manifest).
2. Open the committed gallery and confirm every category — languages, themes, social
   presets, transparent backgrounds, and the accessibility/high-contrast sample —
   still looks correct (no regressions in chrome, padding, syntax colors, or alpha).

See [DESIGN-QA.md](DESIGN-QA.md) for what the gallery covers and how it is enforced.

## Release artifact QA — the clean-Mac checklist

Local debug success is not distribution success. A build that launches fine from
DerivedData on the developer's machine can still be rejected by Gatekeeper, ship an
unsigned bundle, or regress a runtime feature on a user's Mac. Before promotion, verify
the exact **Actions candidate artifact** on a **clean, compatible Mac** — one that
has never had this repository or any DerivedData on it (a spare machine, a fresh VM,
or a freshly created user account). That is the environment a user installs into, and
the only place this check is meaningful.

`scripts/qa-release.sh` drives it. The script is deliberately self-contained: it needs
only the artifact and the stock macOS command-line tools (`codesign`, `spctl`,
`stapler`, `hdiutil`, `plutil`, `lipo`, `base64`, `sw_vers`, `uname`, `stat`), so it can run
without the repository. The candidate artifact also contains
`Vitrine-<version>-qa-handoff.zip`: the exact DMG, checksum, SBOM, appcast, cask update,
release notes, QA script, real-WebKit fixtures, and a structured log template in one
checksummed bundle. Use that ZIP for external qualification rather than assembling files
by hand. Manual promotion reruns the automated suite before publication; the
`published-qa` job downloads and validates the public bytes once more before downstream
channels move.

```bash
# On each clean Mac, after extracting the candidate handoff ZIP:
cd Vitrine-1.2.0-qa-handoff
shasum -a 256 -c SHA256SUMS
./qa-release.sh Vitrine-1.2.0.dmg
# or, against an already-extracted app:
./qa-release.sh /Applications/Vitrine.app
# with no argument it auto-detects the newest dist/*.dmg.
```

**What it records.** Every run prints a QA environment header so a pass or fail is tied
to a known machine and artifact: the **macOS version**, the hardware **architecture**
(`uname -m`), the artifact's **app version** (`CFBundleShortVersionString` +
`CFBundleVersion`), the bundle identifier, and the **signing identity** (the Developer
ID `Authority`, or a clear "unsigned/ad-hoc" marker). Capture that header in the
release QA log.

**What it checks automatically.** The signing/notarization assessment a user's
Gatekeeper runs at first launch, plus a bundle sanity check — on both the DMG and the
app inside it: `codesign --verify --deep --strict`, the hardened-runtime flag, `spctl
-a` (Gatekeeper validation), `stapler validate` (so first launch works offline), and
`plutil` Info.plist validation (including `LSUIElement`, the no-Dock-icon marker).
It also requires the embedded `VitrineMenuBarHelper` executable and proves that its
signature binds the stable `com.johnny4young.vitrine.menubar-helper` identifier and
retains `com.apple.security.app-sandbox` plus
`com.apple.security.inherit`. It enumerates every executable Mach-O in the downloaded app with
`lipo -archs` and rejects the artifact if the app, embedded CLI, helper, framework, or
XPC service lacks either arm64 or x86_64. For the direct-download PRO channel, it additionally
requires `VitrineLicenseSigningKey` to exist and decode to exactly 32 bytes. That check
uses private mode-`0600` temporary files and reports only pass/fail — it never prints the
embedded private key. The same artifact check requires
`SUEnableInstallerLauncherService = YES`, an embedded Sparkle `Installer.xpc`, and final
`network.client` plus matching `-spks` / `-spki` entitlements; it rejects the unnecessary
Downloader service because this app already has direct network access.

**App bug vs. signing failure.** A failed check is classified and the **exit code says
which class** it is, because the two have completely different owners and fixes:

- exit `3` — an **app / packaging** problem (missing or malformed bundle, bad
  `Info.plist`, missing `LSUIElement`): fix the app, not the pipeline.
- exit `2` — a **signing / notarization** failure (broken signature, hardened runtime
  off, Gatekeeper rejection, missing staple): fix the certificate, notarization, or
  stapling — never the code.
- exit `0` — every automated check passed; now walk the manual checklist.
- exit `1` — the artifact could not be found or mounted (usage/environment error).

An **unsigned local dev DMG** exits with signing status `2`: it is expected to be
rejected by Gatekeeper and is **never production-ready**. `build-dmg.sh` still permits
unsigned local packaging, but release QA deliberately cannot report that artifact as a
successful distribution candidate.

**The manual checklist** (the script prints it; no headless check can prove these
interactive behaviors — walk each on the clean Mac and record pass/fail per release):

1. **DMG opens** — double-clicking the `.dmg` shows the volume window.
2. **Drag to Applications** — drag `Vitrine.app` onto the Applications alias.
3. **First launch** — opening it from `/Applications` launches past Gatekeeper with no
   "unidentified developer" block (requires a signed + notarized build).
4. **Gatekeeper** — no "developer cannot be verified" dialog on first launch.
5. **Menu-bar icon** — the Vitrine icon appears in the menu bar.
6. **No Dock icon** — Vitrine shows no Dock icon and no Cmd-Tab entry (`LSUIElement`).
7. **Quick capture** — Quick Capture renders the clipboard/selection to an image.
8. **Editor export** — the editor exports a PNG that opens and looks correct.
9. **Settings** — Settings panes load and a changed setting persists across relaunch.
10. **Launch at login** — toggling it on auto-starts Vitrine after a re-login/reboot;
    toggling it off stops that.
11. **PRO activation** — while online, open a PRO-gated action, paste the dedicated live
    QA license into the masked field, activate, and confirm the sheet closes and PRO
    unlocks. Never put the raw license key in a screenshot, shell history, or QA log.
12. **Offline relaunch** — quit, disconnect every network interface, relaunch, and confirm
    PRO remains unlocked and a PRO-only multi-size export succeeds.
13. **PRO CLI** — still offline, run the bundled `vitrine-cli multi-size` path and confirm
    it writes the requested images. This proves the separate process accepts the app's
    signed token; a basic render is not sufficient because basic terminal capture may be
    free in a later tier contract.
14. **Token permissions** — without reading or printing it, confirm the non-empty
    `pro-license.token` mirror has POSIX mode exactly `0600`.
15. **N to N+1 update** — install the previous direct-download release in a disposable QA
    location, choose **Check for Updates…**, click **Install Update**, and confirm Vitrine
    relaunches on the candidate version without an installer or authorization error.
16. **Real local HTML WebKit** — disconnect every network interface, copy
    `webkit/local-safe.html` with `pbcopy`, trigger Vitrine, and export a snapshot that
    visibly contains `VITRINE_LOCAL_SAFE`. The deterministic UI-test renderer is not
    acceptable evidence for this step.
17. **Remote subresource blocked** — reconnect, run
    `webkit/verify-remote-probe.sh evidence before`, copy
    `webkit/remote-resource-blocked.html`, trigger Vitrine, export the rendered
    `REMOTE_REQUEST_FAILED — VERIFY CONTROL` marker, and then run
    `webkit/verify-remote-probe.sh evidence after`. Both controls must succeed and their
    PNG bytes must be identical. `REMOTE_LOADED — FAIL` is a release blocker. The
    rendered `onerror` marker alone is not sufficient evidence.
18. **Real public URL WebKit** — copy `https://example.com`, accept the disclosure when
    shown, and export a real non-placeholder capture of the page.
19. **Loopback rejected immediately** — submit the `127.0.0.1` entry from
    `webkit/blocked-destinations.txt` and require the domain error before WebKit navigation
    begins; a later timeout is not a pass.
20. **Private destinations rejected immediately** — repeat with the private and
    link-local entries and require the same pre-navigation rejection.
21. **Uninstall** — quitting and trashing the app (or `brew uninstall --cask vitrine`)
    leaves no menu-bar icon and no login item behind.

These fixtures intentionally do **not** certify public-to-private redirect revalidation.
That policy remains protected by deterministic navigation-delegate tests; never mark it as
clean-Mac validated from this manual journey.

Complete both platform entries in `webkit/qualification-log.json`, change
`overallStatus` only after every required scenario passes, and keep screenshots/exports in
the handoff's `evidence/` directory. For PRO, record only the dedicated QA license label or a
**redacted** order/license identifier and the outcome. **Never record** the raw license key,
embedded private signing key, token contents, private page data, or cookies. Before the first
public sale — and whenever checkout, pricing, fulfillment email, or product configuration
changes — also complete a production-mode checkout from the public website and confirm the
license email arrives. The optional
`codesign`/`spctl`/`plutil`/`stapler` checks above run automatically; the interactive items
above are the manual half. See [`ACTIVATION.md`](ACTIVATION.md) for exact secret-safe CLI and
token-permission commands.

The direct-download lifecycle can deactivate seats created by current builds because the
activation record retains the exact provider instance. Include that explicit Settings →
About action in buyer-journey QA when activation/deactivation code changes. Activations
created by older builds without that record still require the purchase portal or support.
Automatic cross-device Restore and periodic remote seat/refund re-validation remain out of
scope. Upgrades/offline relaunches preserve the local token; a clean Mac activates the
license again.

## Checklist

- [ ] `make test` green (includes the launch-gallery render regression + artifact checks)
- [ ] `make icon` up to date
- [ ] Version bumped in `project.yml` (`MARKETING_VERSION`) and the cask
- [ ] `CHANGELOG.md` updated: promote `[Unreleased]` to `## [x.y.z] - YYYY-MM-DD`, open a
      fresh `[Unreleased]`, refresh the compare links, then `make changelog-check`
- [ ] Release note added to `Vitrine/Help/ReleaseNotes.swift` (newest first; version
      matches `MARKETING_VERSION`), and `docs/HELP.md` updated if Help content changed
- [ ] Website release highlights updated in `site/` (English and Spanish); `cd site &&
      npm test` confirms their version matches `MARKETING_VERSION`
- [ ] **Visual review against the launch gallery** done (re-run `make gallery` if a
      visual change landed; review the `Tests/Fixtures/Samples/` diff) — see DESIGN-QA.md
- [ ] `UI tests` CI job green on the release commit (or `make test-ui` run locally)
- [ ] Tag pushed; release workflow `verify` gate and DMG publish both green
- [ ] Tap PR opened: cask `version` + `sha256` set from the release's
      `vitrine-cask-update.txt`, `brew audit --cask --strict` green in the tap, and
      `brew install`/`brew uninstall --cask` smoke-tested on a clean Mac
- [ ] **Release artifact QA on a clean Mac** done: `scripts/qa-release.sh` run against
      the published DMG, its environment header + manual checklist recorded in the
      release QA log (including secret-safe online activation, offline relaunch,
      PRO-only CLI multi-size, `0600` token proof, and all installed-candidate WebKit
      fixtures), the structured Sequoia and Tahoe entries completed, and any failure
      triaged as app bug vs. signing/notarization
