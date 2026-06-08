# Pre-launch setup & publishing guide

> **What this is.** [`RELEASING.md`](RELEASING.md) and [`APP-STORE.md`](APP-STORE.md)
> document how to *run* the release pipeline. They assume you already hold the Apple
> credentials, signing keys, and distribution accounts. This file is the missing half:
> the **one-time, manual, off-repo setup** you must do before that pipeline can ship a
> real build — how to get each account/credential, the **naming** decisions to lock in,
> the in-repo **placeholders** to fill, and **advice for publishing** the app.
>
> Nothing here is code. The code, CI, and pipeline scaffolding are done and green; what
> remains is human: open accounts, generate keys, fill placeholders, and announce.

---

## 0. Status at a glance

| Area | State | Who/what does it |
| --- | --- | --- |
| App code, tests, CI | ✅ Done, green | The repo |
| Release pipeline (DMG, notarize, Sparkle appcast, cask template, QA scripts) | ✅ Scaffolded | `release.yml`, `scripts/*` |
| App Store dry-run pipeline | ✅ Scaffolded | `appstore.yml` |
| Apple Developer account | ⬜ **You, manually** | §1 |
| Developer ID certificate (.p12) | ⬜ **You, manually** | §2 |
| App Store Connect API key (.p8) | ⬜ **You, manually** | §2 |
| Sparkle EdDSA keys | ⬜ **You, manually** | §3 |
| GitHub repo secrets | ⬜ **You, manually** | §4 |
| GitHub Pages (Sparkle feed) | ⬜ **You, manually** | §5 |
| Homebrew tap repo | ⬜ **You, manually** | §5 |
| Naming decisions locked | ⬜ **Decide before first tag** | §6 |
| In-repo placeholders filled | ⬜ 3 placeholders | §7 |
| First release + announce | ⬜ After the above | §8–§9 |

**Minimum to ship a trustworthy direct-download DMG:** §1 → §2 (Developer ID + notary
key) → §4 (secrets) → §7 (fill `DEVELOPMENT_TEAM`) → tag. Sparkle (§3), the tap (§5),
and the App Store (§8) are each independent add-ons you can do later.

---

## 1. Apple Developer Program account

Everything Apple-signed (notarization, Developer ID, the App Store) requires a paid
membership. The free Apple ID is **not** enough for notarization or Developer ID.

- **Where:** <https://developer.apple.com/programs/> → *Enroll*.
- **Cost:** USD **$99/year** (individual or organization). An organization enrollment
  needs a D-U-N-S number and takes longer; an **individual** enrollment is fine for a
  solo open-source app and is faster.
- **Time:** minutes to a few days (identity verification can lag).
- **What it unlocks:** Developer ID certificates, the notary service, App Store Connect,
  and your 10-character **Team ID** (needed everywhere below).
- **Find your Team ID:** <https://developer.apple.com/account> → *Membership details* →
  *Team ID* (e.g. `A1B2C3D4E5`).

> If you only ever want the App Store channel, you still need this. If you only ever want
> the DMG channel, you still need this (notarization is mandatory for Gatekeeper).

---

## 2. Signing & notarization credentials

Two things: a **Developer ID Application certificate** (signs the app) and an **App
Store Connect API key** (notarizes it, and later uploads to the App Store).

### 2a. Developer ID Application certificate → `.p12`

This is the identity Gatekeeper trusts for a direct download.

> **Know this first (Apple nuance):** a Developer ID Application certificate is **team-wide,
> not per-app** — Apple ties it to your *account*, the **same** cert signs every
> direct-download app you ever ship, and its name is fixed by Apple
> (`Developer ID Application: Your Name (TEAMID)`), so there is no "Vitrine-only" signing
> cert. Since you don't have one yet, you create it now (your first); just **don't create
> another one per app later** — Apple caps how many you can hold. The things you genuinely
> label/scope per-app are the **notary API key** (§2b), the **Sparkle keys** (§3), and the
> **repo secrets** (§4). Name the exported `.p12` whatever you like (e.g.
> `vitrine-developer-id.p12`), knowing the cert inside is your shared team identity.

1. Easiest path — **Xcode**: *Settings ▸ Accounts ▸* (your Apple ID) *▸ Manage
   Certificates ▸ + ▸ Developer ID Application*. Xcode creates it and stores the private
   key in your login Keychain.
   - Manual path: *Keychain Access ▸ Certificate Assistant ▸ Request a Certificate from a
     Certificate Authority* (save a CSR), then upload it at
     <https://developer.apple.com/account/resources/certificates> → *+* → **Developer ID
     Application**, download the `.cer`, and double-click to install.
2. **Export the `.p12`** (cert **+** private key): in *Keychain Access*, find *Developer
   ID Application: …*, right-click ▸ **Export**, choose `.p12`, set a strong **export
   password** (you'll store it as a secret).
3. Note the **identity name** exactly: `Developer ID Application: Your Name (TEAMID)`.
   List it any time with:
   ```bash
   security find-identity -v -p codesigning
   ```

### 2b. App Store Connect API key → `.p8` (preferred for notarization & App Store)

One key both **notarizes** the DMG (CS-061) and **uploads** App Store builds (CS-062).

1. <https://appstoreconnect.apple.com> → *Users and Access ▸ Integrations ▸ App Store
   Connect API* → **Generate API Key**. **Name it `Vitrine CI`** so it is a dedicated,
   independently-revocable key for this app; a *Developer*-level role is enough for
   notarization (and later App Store uploads). The key technically can notarize any app on
   the team, but naming it for Vitrine is what lets you revoke it without touching anything
   else.
2. **Download the `.p8` immediately — it is shown only once.** Store it securely (a
   password manager); losing it means generating a new one.
3. Record the **Key ID** (10 chars) and the **Issuer ID** (a UUID shown above the keys
   list). You now have the trio: `.p8` file, Key ID, Issuer ID.

> The Apple-ID-and-app-specific-password style still works as a fallback (see the table
> in [`RELEASING.md`](RELEASING.md#credentials-repository-secrets)), but the API key is
> preferred — no password rotation, and it doubles for App Store uploads.

---

## 3. Sparkle auto-update keys (EdDSA) — optional, for the DMG channel

Only needed if you want the direct-download build to auto-update. The App Store channel
ignores Sparkle entirely. Full flow: [`RELEASING.md` ▸ Auto-update](RELEASING.md#auto-update-sparkle--cs-064).

> **Do this _before_ tagging v0.1.0.** macOS reads `SUPublicEDKey` at launch, so the
> public key must already be embedded in the **first** shipped build. If v0.1.0 ships with
> the placeholder key, that installed base can **never** auto-update — every user would
> have to re-download the DMG by hand to reach v0.2.0. Generating the keys and filling the
> placeholder (§7) is therefore a **pre-v0.1.0 requirement**, not a later step. Skip all of
> §3 only if you deliberately don't want auto-update at all.

1. Download a Sparkle release (`Sparkle-<version>.tar.xz`) from
   <https://github.com/sparkle-project/Sparkle/releases> and run its tool:
   ```bash
   ./bin/generate_keys        # prints the PUBLIC key; stores the PRIVATE key in your Keychain
   ```
2. Put the **public** key in the repo (§7): `Info.plist` → `SUPublicEDKey`.
3. Export the **private** key and store it as a GitHub secret, then delete the local copy:
   ```bash
   ./bin/generate_keys -x sparkle_private_key.pem
   gh secret set SPARKLE_EDDSA_PRIVATE_KEY < sparkle_private_key.pem
   rm sparkle_private_key.pem
   ```

> Back up the private key like the Developer ID cert. Losing it means the installed base
> can no longer verify (and therefore install) any future update.

---

## 4. GitHub repository secrets

Set these on `johnny4young/vitrine` (*Settings ▸ Secrets and variables ▸ Actions*), or
with the `gh` CLI. Each pipeline stage is **gated** on its secret and **skips cleanly**
when absent — so you can add them incrementally and a fork still gets a green unsigned
build.

| Secret | From | Needed for |
| --- | --- | --- |
| `MACOS_NOTARY_TEAM_ID` | §1 Team ID | Signing + notarization (also `DEVELOPMENT_TEAM`) |
| `MACOS_CODE_SIGN_IDENTITY` | §2a identity name | Signing the app/DMG |
| `MACOS_CERTIFICATE_P12` | §2a `.p12`, base64 | Importing the cert on the runner |
| `MACOS_CERTIFICATE_PASSWORD` | §2a export password | Decrypting the `.p12` |
| `MACOS_NOTARY_KEY_P8` | §2b `.p8`, base64 | Notarization (preferred) |
| `MACOS_NOTARY_KEY_ID` | §2b Key ID | Notarization |
| `MACOS_NOTARY_KEY_ISSUER_ID` | §2b Issuer ID | Notarization |
| `SPARKLE_EDDSA_PRIVATE_KEY` | §3 private key | Signing the Sparkle appcast |

Base64-and-set the file secrets straight from the source files:

```bash
base64 -i DeveloperID.p12          | gh secret set MACOS_CERTIFICATE_P12
base64 -i AuthKey_XXXXXXXXXX.p8     | gh secret set MACOS_NOTARY_KEY_P8
gh secret set MACOS_CODE_SIGN_IDENTITY  --body "Developer ID Application: Your Name (TEAMID)"
gh secret set MACOS_NOTARY_TEAM_ID      --body "TEAMID"
gh secret set MACOS_NOTARY_KEY_ID       --body "XXXXXXXXXX"
gh secret set MACOS_NOTARY_KEY_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set MACOS_CERTIFICATE_PASSWORD --body "•••"
```

> **Never commit any of these.** They live only as GitHub secrets and in your password
> manager. The repo is public.

---

## 5. Distribution infrastructure (create once)

### 5a. GitHub Pages — hosts the Sparkle appcast

`Info.plist`'s `SUFeedURL` is `https://johnny4young.github.io/vitrine/appcast.xml`. For
that URL to resolve, enable Pages on this repo: *Settings ▸ Pages ▸ Build and deployment ▸
Source = GitHub Actions*. `release.yml` then deploys the signed `appcast.xml` there on
each tagged release. (No Pages = no auto-update feed; the DMG still ships.)

### 5b. Homebrew tap — `johnny4young/homebrew-tap`

So users can `brew install --cask johnny4young/tap/vitrine`:

1. Create a **public** repo named exactly **`homebrew-tap`** under your account.
2. Add `Casks/vitrine.rb` — a copy of this repo's [`packaging/Casks/vitrine.rb`](../packaging/Casks/vitrine.rb)
   with the real `version` and `sha256` (the release publishes a ready-to-paste
   `vitrine-cask-update.txt`; see [`RELEASING.md` ▸ Homebrew](RELEASING.md#homebrew-cask--cs-063)).
3. Audit + smoke-test in the tap before announcing (commands in `RELEASING.md`).

> The cask's `sha256` placeholder (all zeros) in this repo is intentional — the **real**
> checksum only exists once a DMG is published, and the release computes it for you.

---

## 6. Naming — lock these in **before** the first tag

Some names are effectively permanent once the installed base or the App Store has them.
Decide deliberately now.

| Surface | Current value | Changeable later? | Action |
| --- | --- | --- | --- |
| Bundle identifier | `com.johnny4young.vitrine` | ❌ **Immutable** once installed/on the App Store | **Decided.** Register it as an **App ID** (Developer portal ▸ Identifiers ▸ +) so the App Store recognizes it. Follows your `com.johnny4young.*` scheme, distinct from your other apps. |
| App display name | `Vitrine` | App Store: hard; binary: easy | App Store names are **globally unique** — confirm "Vitrine" is free when you create the App Store record; keep a fallback like **"Vitrine — Code to Image"**. |
| Homebrew cask token | `vitrine` | Cheap pre-adoption | Keep. |
| Tap repo | `johnny4young/homebrew-tap` | — | Create (§5b). |
| Sparkle feed host | `johnny4young.github.io/vitrine` | tied to repo name | Keep, or move to a custom domain later. |
| Marketing domain | _(none)_ | — | **Optional:** grab `vitrine.app` for a landing page + a stable download URL (not required — the bundle ID no longer implies a domain). |

**On `com.johnny4young.vitrine`:** this follows your account's `com.johnny4young.*`
reverse-DNS scheme, so Vitrine sits cleanly alongside your other apps while sharing no
identity with them. It is reused as the app's **log subsystem**, **App Intent id**, and
**Sparkle XPC names**, so it is already wired consistently across the repo. The bundle ID is
the one truly irreversible choice — changing it after release orphans every installed copy
and forces a new App Store listing.

**Trademark sanity check:** "Vitrine" is a common word (French/architectural for *display
case/showcase*), so trademark risk is low, but do a quick search for an existing macOS dev
tool of the same name before you print it on a release.

---

## 7. In-repo placeholders to fill

Three committed placeholders currently keep the repo building **without** an Apple account.
Fill them as you complete the steps above (each is a small, explicit edit):

| Placeholder | File | Replace with | After step |
| --- | --- | --- | --- |
| `DEVELOPMENT_TEAM: ""` | `project.yml` | Your 10-char Team ID | §1 |
| `SUPublicEDKey` = `REPLACE_WITH_SPARKLE_EDDSA_PUBLIC_KEY` | `Vitrine/Resources/Info.plist` | Sparkle public key | §3 |
| cask `sha256` = all-zeros | `packaging/Casks/vitrine.rb` (template) | _leave as-is_ — the **tap** copy gets the real checksum per release | §5b |

> Bumping `DEVELOPMENT_TEAM` is also available via the `MACOS_NOTARY_TEAM_ID` secret for
> CI signing; set the `project.yml` value only if you also build/sign locally.

---

## 8. Choosing the channel(s)

You can ship either or both. They share **one** app target — no divergent builds.

| | Direct-download DMG (primary) | Mac App Store (optional) |
| --- | --- | --- |
| Gate | Notarization (automated) | Human App Review (days) |
| Updates | Sparkle, instant | App Store, on its cadence |
| Reach | Power users, `brew`, your site | Casual discovery, search |
| Cut | $99/yr + the steps above | + App Store record, screenshots, review notes |
| Recommended first | ✅ **Ship this first** | Add later if you want discoverability |

**Recommendation:** ship the **notarized DMG + Homebrew cask** for v0.1.0 (it's the
fastest path to a trustworthy install and matches a dev-tool audience). Treat the App
Store as a **post-v0.1** follow-up — `appstore.yml` and [`APP-STORE.md`](APP-STORE.md) are
already prepared for it, including the App Review notes to paste.

---

## 9. The first release & publishing advice

### 9a. Cut the release (mechanics in `RELEASING.md`)

The short version once §1–§7 are done:

1. Fill `DEVELOPMENT_TEAM`, bump `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` if needed,
   add a `ReleaseNotes.swift` entry, `make icon` if the icon changed.
2. `make lint && make build && make test` green; run `make test-ui` locally once.
3. `git tag v0.1.0 && git push origin v0.1.0` → `release.yml` builds, signs, notarizes,
   and publishes the DMG + `appcast.xml`.
4. **Clean-Mac QA** with `scripts/qa-release.sh` against the *published* DMG (§ the
   CS-066 checklist in `RELEASING.md`) — the only check that proves a stranger's Mac
   accepts it.
5. Open the tap PR (paste `vitrine-cask-update.txt`); smoke-test `brew install`.

### 9b. Have these ready before you announce

- **README that sells in 5 seconds:** a looping **GIF/screen-capture** of Quick Capture →
  image at the very top (use Vitrine itself for the code shots). The tagline is already
  good; add an animated demo.
- **3–5 polished sample images** (you can render them with `make gallery`).
- **Install one-liner** front and center: `brew install --cask johnny4young/tap/vitrine`.
- A short **CHANGELOG**/release notes (the in-app "What's New" already covers users).
- Optional: a tiny **landing page** at `vitrine.app` (even a one-pager) — lends legitimacy
  and gives non-GitHub users somewhere to land.

### 9c. Where to launch (a dev tool's audience)

- **Show HN** ("Show HN: Vitrine – turn code into images from your macOS menu bar"). Post
  in the morning ET on a weekday; be present in the thread to answer.
- **Product Hunt** — schedule for 00:01 PT; line up the GIF + first comment.
- **Reddit:** r/macapps, r/swift, r/MacOS (read each subreddit's self-promo rules first).
- **Lobsters**, **Hacker News**, **Mastodon/Bluesky/X** dev communities, and any
  Swift/macOS Discord/Slack you're in.
- **GitHub hygiene that compounds:** set repo **topics** (`macos`, `swift`, `swiftui`,
  `menu-bar`, `developer-tools`, `code-to-image`), a crisp description, and a pinned
  release. Stars and the Homebrew cask are the social proof that pulls the next user.

### 9d. After launch

- **Measure without telemetry** (the app collects none, by design): GitHub stars, release
  **download counts**, `brew` analytics (`brew info --cask vitrine`), and issue volume.
- **Cadence:** ship small, frequent Sparkle updates — a smooth first auto-update is a
  strong trust signal. Bump `CURRENT_PROJECT_VERSION` every release or Sparkle won't see
  the build as newer.
- **Triage** issues/PRs quickly in the first week; first impressions set the tone for an
  open-source project.
- **Sustainability (optional):** GitHub Sponsors / "Buy me a coffee" link in the README;
  the MIT license already invites contribution.

---

## 10. One-time setup checklist

- [ ] Apple Developer Program enrolled; Team ID in hand (§1)
- [ ] Developer ID Application cert exported as `.p12` (+ password) (§2a)
- [ ] App Store Connect API key `.p8` + Key ID + Issuer ID saved (§2b)
- [ ] Sparkle EdDSA keys generated; private key backed up (§3, if using auto-update)
- [ ] All GitHub secrets set (§4)
- [ ] GitHub Pages enabled (§5a) and Homebrew tap repo created (§5b)
- [ ] Bundle ID registered as an App ID; app name availability confirmed (§6)
- [ ] `DEVELOPMENT_TEAM` + `SUPublicEDKey` placeholders filled (§7)
- [ ] First `v0.1.0` tag cut; DMG notarized + clean-Mac QA passed (§9a)
- [ ] README GIF + install one-liner + samples ready (§9b)
- [ ] Announced (§9c)
