# Releasing Vitrine (CS-012)

Vitrine ships as a signed, notarized DMG attached to a GitHub release, installable
via a Homebrew cask. The pipeline degrades gracefully: without signing secrets it
still produces an **unsigned** DMG (fine for local testing).

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

The workflow builds the Release app, optionally signs + notarizes it, creates the
DMG, and publishes a GitHub release with auto-generated notes.

## Signing & notarization

Set these repository secrets to enable signing + notarization (otherwise both are
skipped and the DMG is unsigned):

| Secret | Purpose |
| --- | --- |
| `MACOS_CODE_SIGN_IDENTITY` | Developer ID Application identity name |
| `MACOS_NOTARY_APPLE_ID` | Apple ID for `notarytool` |
| `MACOS_NOTARY_PASSWORD` | App-specific password |
| `MACOS_NOTARY_TEAM_ID` | Developer Team ID |

The signing certificate itself must be imported into the runner keychain (e.g. with
`apple-actions/import-codesign-certs`) — add that step when you have a Developer ID.

## Homebrew cask

`packaging/Casks/vitrine.rb` is the cask template. On each release:

1. Bump `version`.
2. Replace `sha256 :no_check` with the DMG checksum printed by `build-dmg.sh`.
3. Publish it to a tap (e.g. `johnny4young/homebrew-tap`) so users can
   `brew install --cask johnny4young/tap/vitrine`.

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

## Auto-update (Sparkle) — follow-up

Sparkle integration (appcast feed + EdDSA signing) is planned: add the `Sparkle`
SPM package, host `appcast.xml`, and point `SUFeedURL` at it. Tracked as a
follow-up to CS-012; not required for the first manual release.

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

## Checklist

- [ ] `make test` green (includes the launch-gallery render regression + artifact checks)
- [ ] `make icon` up to date
- [ ] Version bumped in `project.yml` (`MARKETING_VERSION`) and the cask
- [ ] Release note added to `Vitrine/Help/ReleaseNotes.swift` (newest first; version
      matches `MARKETING_VERSION`), and `docs/HELP.md` updated if Help content changed
- [ ] **Visual review against the launch gallery** done (re-run `make gallery` if a
      visual change landed; review the `Tests/Fixtures/Samples/` diff) — see DESIGN-QA.md
- [ ] Tag pushed; release workflow green
- [ ] Cask `sha256` updated to the published DMG
