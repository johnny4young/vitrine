---
name: release
description: Cut a new Vitrine release — bump the version, verify build/test/lint, build the DMG, tag, push, and prepare the Homebrew cask bump. Run this when the user wants to ship a version (e.g. "/release 0.2.0").
disable-model-invocation: true
---

# Release Vitrine

Orchestrate a Vitrine release end to end. This skill has **side effects** (git tag, push,
release artifact) — it is user-invoked only. **Never** push a tag without explicit
confirmation from the user in this turn.

The target version comes from the argument (e.g. `/release 0.2.0`). If none is given, read
the current `MARKETING_VERSION` from `project.yml` and propose the next patch, then ask.

## Source of truth

- Version lives in **`project.yml`** → `settings.base.MARKETING_VERSION` (the Info.plist
  uses `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, so only `project.yml` changes).
- `CURRENT_PROJECT_VERSION` is the build number — bump it by 1 each release.
- Tag format is **`vX.Y.Z`**. Pushing a `v*` tag triggers `.github/workflows/release.yml`,
  which builds the DMG on `macos-latest` and publishes a GitHub Release with auto-generated
  notes. Signing/notarization run only if the `MACOS_*` repo secrets are set; otherwise the
  DMG is unsigned (the workflow no-ops the notary step).
- `scripts/build-dmg.sh` builds Release + DMG locally and prints the **sha256** (used for
  the Homebrew cask).
- `packaging/Casks/vitrine.rb` needs `version` bumped and `sha256 :no_check` replaced with
  the real checksum after the DMG exists.
- See `docs/RELEASING.md` for the canonical human-facing process — read it and defer to it
  if it disagrees with these steps.

## Steps

1. **Preflight.** Confirm a clean working tree (`git status --porcelain` empty) and that the
   current branch is the release branch (usually `main`). Read `docs/RELEASING.md`. Resolve
   the target version `X.Y.Z`; confirm it with the user if it was not passed as an argument.

2. **Bump the version.** Edit `project.yml`:
   - set `MARKETING_VERSION` to `X.Y.Z`
   - increment `CURRENT_PROJECT_VERSION` by 1
   Then run `xcodegen generate` (the PostToolUse hook also does this on edit).

3. **Verify green.** Run, and stop on any failure:
   - `make lint`
   - `make build`
   - `make test`
   Report the results (test count / suites). Do not proceed if anything is red.

4. **Build the DMG locally.** `VERSION=X.Y.Z ./scripts/build-dmg.sh`. Capture the printed
   `sha256` of `dist/Vitrine-X.Y.Z.dmg`. (This is a local sanity build; CI rebuilds it.)

5. **Bump the Homebrew cask.** Edit `packaging/Casks/vitrine.rb`: set `version "X.Y.Z"` and
   replace `sha256 :no_check` with the sha256 from step 4.

6. **Commit.** Stage `project.yml` and `packaging/Casks/vitrine.rb` (plus any regenerated
   files that are tracked) and commit: `Release vX.Y.Z`.
   IMPORTANT: do **not** add AI co-authorship / "generated-by" trailers to the commit
   (per the user's global preference). Plain message only.

7. **Confirm, then tag + push.** Show the user the diff and the exact commands. Only after an
   explicit "yes" in this turn:
   - `git tag vX.Y.Z`
   - `git push origin <branch>`
   - `git push origin vX.Y.Z`   ← this triggers the Release workflow.

8. **Watch the release.** If the GitHub MCP server (or `gh`) is available, watch the
   `Release` workflow run and report the published release URL. Otherwise tell the user where
   to find it: `https://github.com/johnny4young/vitrine/releases`.

9. **Post-release.** Remind the user that the cask sha256 must match the **CI-built** DMG if
   it differs from the local one (signed vs. unsigned builds differ); if a Homebrew tap
   exists, the cask bump may need a separate PR there.

## Guardrails

- Pushing tags and publishing releases are irreversible-ish — always confirm in-chat first.
- Never enter Apple ID / notarization / signing credentials yourself; those live in repo
  secrets or the user's Keychain.
- If the working tree is dirty or a check fails, stop and report — do not "fix and continue"
  silently.
