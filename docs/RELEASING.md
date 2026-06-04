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

## Auto-update (Sparkle) — follow-up

Sparkle integration (appcast feed + EdDSA signing) is planned: add the `Sparkle`
SPM package, host `appcast.xml`, and point `SUFeedURL` at it. Tracked as a
follow-up to CS-012; not required for the first manual release.

## Checklist

- [ ] `make test` green
- [ ] `make icon` up to date
- [ ] Version bumped in `project.yml` (`MARKETING_VERSION`) and the cask
- [ ] Tag pushed; release workflow green
- [ ] Cask `sha256` updated to the published DMG
