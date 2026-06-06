# Releasing Vitrine (CS-012)

Vitrine ships as a Developer ID-signed, notarized DMG attached to a GitHub release,
installable via a Homebrew cask. The pipeline degrades gracefully: without signing
secrets it still produces an **unsigned** DMG for local development — but that
unsigned build is **never production-ready** (Gatekeeper rejects it). See
[Signing, notarization & Gatekeeper (CS-061)](#signing-notarization--gatekeeper-cs-061).

## One command, locally

```bash
VERSION=0.1.0 ./scripts/build-dmg.sh
# → dist/Vitrine-0.1.0.dmg  (+ prints the SHA-256)
```

## Tagged release (CI)

Pushing a tag triggers `.github/workflows/release.yml`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds the Release app, signs + notarizes it when the signing secrets
are configured (CS-061), verifies the signature and runs a Gatekeeper assessment,
creates the DMG, and publishes a GitHub release with auto-generated notes.

## Continuous integration (CS-060)

CI is a release gate, not just a compile check.

- **`.github/workflows/ci.yml`** runs on every push to `main` and every pull
  request. Before building, it records the exact toolchain — macOS image, Xcode,
  and Swift versions — into the job summary, so a green or red result is always
  tied to a known environment. It validates every workflow's YAML, then runs
  `make lint`, `make build`, `make build-ui-tests`, and `make test`. The Swift
  Package Manager download cache is restored between runs (keyed on `project.yml`,
  the dependency source of truth) to cut build time without risking a stale build.
- **`.xcresult` on failure.** The build and test steps pass `RESULT_BUNDLE=…` to
  `make`, and on any failure CI uploads the resulting `.xcresult` bundles (plus the
  golden-diff and launch-gallery artifacts) so a failure can be triaged offline
  without re-running CI.
- **Weekly drift watch.** A scheduled run (Mondays 08:00 UTC, also available via
  *Run workflow*) re-runs the full gate against the current `macos-latest` image.
  GitHub rolls that image and the bundled Xcode/SDK on its own cadence, which can
  break the build with no code change; the scheduled run surfaces that drift on a
  predictable day instead of on the next unrelated PR.
- **The release workflow refuses to publish a broken build.** `release.yml` runs a
  `verify` job (lint, build, UI-test build, unit tests) that the `publish` job
  `needs:`. A tag therefore cannot publish a DMG unless lint, build, the unit
  suite, and the UI-test compile all pass on the tagged commit.

### Running the UI tests

`make build-ui-tests` (compile only) runs on every PR and in the release gate, and
needs no special permission. **Running the full UI suite (`make test-ui`) is a
local/manual or self-hosted-runner step**, not part of the GitHub-hosted PR gate:
driving the menu-bar app through XCUIAutomation requires the Accessibility /
Automation permission to be granted to the test runner, which is not reliably
available on ephemeral GitHub-hosted macOS runners. Run it locally before a release
(grant the prompt the first time), or wire it into a self-hosted runner that has the
permission pre-granted. Keep this split until GitHub-hosted runners support that
automation permission reliably.

## Signing, notarization & Gatekeeper (CS-061)

Outside the Mac App Store, modern macOS expects a direct download to be **Developer
ID-signed and notarized**, or Gatekeeper blocks first launch. `scripts/build-dmg.sh`
does all of it and degrades gracefully: with no signing identity it still produces an
**unsigned, ad-hoc DMG** for local development. **That unsigned path is for
development only and is never production-ready** — the script prints exactly that and
Gatekeeper rejects the artifact.

What the script does for a signed build:

1. **Signs** the app with the Developer ID Application identity.
2. **Keeps the hardened runtime on** (`ENABLE_HARDENED_RUNTIME=YES`, set in
   `project.yml` and re-asserted on the signed build) — required for notarization.
3. **Verifies** the signature with `codesign --verify --deep --strict --verbose=2`.
4. **Notarizes** with `notarytool` (App Store Connect API key **or** Apple ID
   credentials — see below), then **staples** the ticket to the app, signs the DMG,
   and staples the DMG too so first launch validates offline.
5. **Assesses Gatekeeper** with `spctl -a -vv` on the app and the DMG.

### Credentials (repository secrets)

Signing and notarization are each gated on their secrets; missing ones simply skip
that stage. Notarization accepts **either** credential style — the App Store Connect
API key is preferred for CI (no app-specific password) and wins when both are set.

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

The release workflow imports `MACOS_CERTIFICATE_P12` into a temporary runner keychain
before building (the **Import Developer ID certificate** step), and stages
`MACOS_NOTARY_KEY_P8` to a file (the **Stage App Store Connect API key** step). Both
steps are skipped automatically when their secret is absent, so a fork or a maintainer
without the certificate still gets a green unsigned build.

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

## Homebrew cask — CS-063

The goal is a reliable `brew install --cask johnny4young/tap/vitrine`.

There are two copies of the cask, and the distinction matters:

- **`packaging/Casks/vitrine.rb`** (this repo) is the **source template**. It is the
  single place to evolve the stanzas (name, desc, homepage, URL pattern, livecheck,
  `depends_on`, the `app` artifact, and the `zap` cleanup). It carries a
  **placeholder `sha256`** (all zeros) so it stays valid for `brew style`/`brew audit`
  without claiming to match any real DMG.
- **`Casks/vitrine.rb`** in the tap (`johnny4young/homebrew-tap`) is what users install.
  It is this template with `version` bumped and `sha256` set to the **published DMG's**
  checksum.

### What the release workflow stores for you

`release.yml`'s **Compute and store DMG SHA-256** step runs right after the DMG is
built. It:

- computes the DMG SHA-256 and **prints** it to the run's job summary (visible from the
  Actions run page, no download needed);
- **stores** it as a `Vitrine-<version>.dmg.sha256` sidecar, attached to the GitHub
  release alongside the DMG; and
- writes a ready-to-paste `vitrine-cask-update.txt` (the exact `version "…"` and
  `sha256 "…"` lines), also attached to the release.

So the checksum is never hand-copied off a terminal: it lives on the release.

### Updating the cask in the tap (PR)

After the release publishes, open a PR against `johnny4young/homebrew-tap`:

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

## Release notes (What's New) — CS-049

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

## Auto-update (Sparkle) — CS-064

The **direct-download** build updates itself with [Sparkle](https://sparkle-project.org):
it checks a signed EdDSA appcast and installs the next build without a manual reinstall.
The **Mac App Store** build excludes Sparkle entirely (the App Store owns its own update
mechanism, and a third-party updater is disallowed there) — see
[App Store build excludes Sparkle](#app-store-build-excludes-sparkle) below.

### How it is wired

- **SPM package.** `Sparkle` (2.x) is added in `project.yml` and linked into the app
  target with `embed: true`, so the framework and its Installer/Downloader XPC services
  ship inside the DMG's app bundle.
- **Compilation gate.** Every Sparkle call site is behind `#if VITRINE_DIRECT_DOWNLOAD`.
  The normal build sets that flag (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `project.yml`),
  so the DMG includes Sparkle and a user-visible **Check for Updates…** command (App menu).
  `Vitrine/Updates/SoftwareUpdater.swift` owns the integration.
- **Feed + key in `Info.plist`.** `SUFeedURL` points at the signed appcast on GitHub Pages
  (`https://johnny4young.github.io/vitrine/appcast.xml`); `SUPublicEDKey` is the EdDSA public
  key Sparkle verifies every download against.
- **Direct-download entitlements.** The DMG signs with
  `Vitrine/Resources/Vitrine.DirectDownload.entitlements`, the Phase 1 set **plus**
  `com.apple.security.network.client` (so Sparkle can download) and the two Sparkle XPC
  `mach-lookup` exceptions. `scripts/build-dmg.sh` selects this file via
  `CODE_SIGN_ENTITLEMENTS`. The default and App Store builds keep the minimal
  `Vitrine.entitlements` (no network, no Sparkle), so the Phase 1 "no network" posture in
  [`docs/PERMISSIONS.md`](PERMISSIONS.md) is unchanged.
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

`release.yml`'s **Generate signed Sparkle appcast** step runs in the gated `publish` job
after the DMG is built. Gated on `SPARKLE_EDDSA_PRIVATE_KEY` (so a fork or a pre-key repo
still publishes a DMG, just without an update entry), it:

- signs the DMG with Sparkle's EdDSA tooling and runs `generate_appcast` over `dist/` to
  produce a signed `appcast.xml`, with each item's download URL pointing at the release's
  DMG asset;
- attaches `appcast.xml` to the GitHub release; and
- deploys it to **GitHub Pages**, which is exactly the `SUFeedURL` the app polls.

So a tagged release both ships the DMG and refreshes the feed the installed base updates
from. Sparkle compares the appcast entries to the installed bundle's `CFBundleVersion`, so
remember to bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION`) in `project.yml` for
every release, or Sparkle will not see the new build as newer.

### Testing an update from N to N+1

1. Build and install version *N* from its DMG (`VERSION=N ./scripts/build-dmg.sh`).
2. Tag *N+1* (after bumping the versions in `project.yml`) so the release workflow
   publishes its DMG and the refreshed appcast.
3. Launch the installed *N* and choose **Check for Updates…** — Sparkle should find *N+1*,
   verify its EdDSA signature against `SUPublicEDKey`, and install it. A download whose
   signature does not verify is rejected, which is the man-in-the-middle protection.

### App Store build excludes Sparkle

The optional Mac App Store build removes `VITRINE_DIRECT_DOWNLOAD` from
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` and **strips the Sparkle framework** from the bundle
before archiving (see `.github/workflows/appstore.yml` and
[`docs/APP-STORE.md`](APP-STORE.md)). With the flag absent, `SoftwareUpdater.isSupported`
is `false`, the **Check for Updates…** command is not added to the menu, and no Sparkle code
runs. The App Store entitlements (`Vitrine.entitlements`) stay network-free, so that channel
keeps the documented "no network" posture.

## Visual review — the launch gallery (CS-039)

Vitrine ships with generated design-QA evidence: a launch gallery of representative
screenshots rendered by the app itself, committed under `Tests/Fixtures/Samples/`.
Before tagging:

1. If any visual change landed this cycle, re-run `make gallery` and review the
   `Tests/Fixtures/Samples/` diff (the regenerated PNGs + manifest).
2. Open the committed gallery and confirm every category — languages, themes, social
   presets, transparent backgrounds, and the accessibility/high-contrast sample —
   still looks correct (no regressions in chrome, padding, syntax colors, or alpha).

See [DESIGN-QA.md](DESIGN-QA.md) for what the gallery covers and how it is enforced.

## Release artifact QA — the clean-Mac checklist (CS-066)

Local debug success is not distribution success. A build that launches fine from
DerivedData on the developer's machine can still be rejected by Gatekeeper, ship an
unsigned bundle, or regress a runtime feature on a user's Mac. Before announcing a
release, verify the **published artifact** on a **clean, compatible Mac** — one that
has never had this repository or any DerivedData on it (a spare machine, a fresh VM,
or a freshly created user account). That is the environment a user installs into, and
the only place this check is meaningful.

`scripts/qa-release.sh` drives it. The script is deliberately self-contained: it needs
only the artifact and the stock macOS command-line tools (`codesign`, `spctl`,
`stapler`, `hdiutil`, `plutil`, `sw_vers`, `uname`), so you can copy that one file — or
download it with the release — onto the clean Mac and run it without checking out the
repo.

```bash
# On the clean Mac, against the downloaded release DMG:
./qa-release.sh ~/Downloads/Vitrine-0.1.0.dmg
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
-a` (Gatekeeper acceptance), `stapler validate` (so first launch works offline), and
`plutil` Info.plist validation (including `LSUIElement`, the no-Dock-icon marker).

**App bug vs. signing failure.** A failed check is classified and the **exit code says
which class** it is, because the two have completely different owners and fixes:

- exit `3` — an **app / packaging** problem (missing or malformed bundle, bad
  `Info.plist`, missing `LSUIElement`): fix the app, not the pipeline.
- exit `2` — a **signing / notarization** failure (broken signature, hardened runtime
  off, Gatekeeper rejection, missing staple): fix the certificate, notarization, or
  stapling — never the code.
- exit `0` — every automated check passed; now walk the manual checklist.
- exit `1` — the artifact could not be found or mounted (usage/environment error).

An **unsigned local dev DMG** is reported as a warning, not a failure: it is expected to
be rejected by Gatekeeper and is **never production-ready** (the same posture
`build-dmg.sh` takes).

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
11. **Uninstall** — quitting and trashing the app (or `brew uninstall --cask vitrine`)
    leaves no menu-bar icon and no login item behind.

Record one QA log entry per release (environment header + each checklist result). The
optional `codesign`/`spctl`/`plutil`/`stapler` checks above run automatically; the
interactive items above are the manual half.

## Checklist

- [ ] `make test` green (includes the launch-gallery render regression + artifact checks)
- [ ] `make icon` up to date
- [ ] Version bumped in `project.yml` (`MARKETING_VERSION`) and the cask
- [ ] Release note added to `Vitrine/Help/ReleaseNotes.swift` (newest first; version
      matches `MARKETING_VERSION`), and `docs/HELP.md` updated if Help content changed
- [ ] **Visual review against the launch gallery** done (re-run `make gallery` if a
      visual change landed; review the `Tests/Fixtures/Samples/` diff) — see DESIGN-QA.md
- [ ] `make test-ui` run locally (or on a self-hosted runner) — not in the hosted gate
- [ ] Tag pushed; release workflow `verify` gate and DMG publish both green
- [ ] Tap PR opened: cask `version` + `sha256` set from the release's
      `vitrine-cask-update.txt`, `brew audit --cask --strict` green in the tap, and
      `brew install`/`brew uninstall --cask` smoke-tested on a clean Mac (CS-063)
- [ ] **Release artifact QA on a clean Mac** done: `scripts/qa-release.sh` run against
      the published DMG, its environment header + manual checklist recorded in the
      release QA log, and any failure triaged as app bug vs. signing/notarization
      (CS-066)
