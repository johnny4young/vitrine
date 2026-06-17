# PRO activation — direct-download (Lemon Squeezy) runbook

How to turn on real PRO activation for the **direct-download / Homebrew (DMG)** build. The
activation subsystem is built and tested (CS-090); the remaining release work is your **Lemon
Squeezy account/product**, the release-machine **private-key injection**, and any deliberate
public-key rotation. The Mac App Store channel is separate — see [APP-STORE.md](APP-STORE.md).

## How it works (Architecture B — the app signs locally)

```
user pastes license key
   → LicenseActivationService validates it once online (Lemon Squeezy /v1/licenses/activate)
   → on success the app mints a LicenseToken and signs it LOCALLY with the build-injected
     private key (LicenseSigningKey.embedded)
   → LicenseKeyProvider stores the signed token in the Keychain AND mirrors it to a file
   → every later check (relaunch + the `vitrine` CLI) verifies that token OFFLINE against the
     embedded PUBLIC key — no network, no Lemon Squeezy round-trip
```

Honor/convenience model, not anti-fork DRM (the code is open source). The signature only stops a
hand-edited token and lets the CLI trust the app's activation offline. A build compiled **from
source** has no injected private key, so it cannot mint a token and stays free — which is why the
public repo never grants PRO by itself.

## Prerequisites

- A [Lemon Squeezy](https://lemonsqueezy.com) account (Merchant of Record — handles global VAT).
- This repo, able to build the DMG (`scripts/build-dmg.sh`).

## Step 1 — Generate your signing keypair

```sh
swift scripts/generate-license-keypair.swift
```

It prints a **PUBLIC** and a **PRIVATE** base64 value. They are a pair: a token signed with
PRIVATE verifies only against PUBLIC. Keep the PRIVATE value secret (your Keychain or a password
manager). **Never commit it.**

## Step 2 — Embed the PUBLIC key (in source — not secret)

In [`Vitrine/Pro/LicenseKey.swift`](../Vitrine/Pro/LicenseKey.swift), confirm
`LicenseVerifier.embedded` matches your public key. If you are rotating keys, replace the literal:

```swift
static let embedded = LicenseVerifier(
    publicKey: try! Curve25519.Signing.PublicKey(
        rawRepresentation: Data(base64Encoded: "<YOUR PUBLIC BASE64>")!))
```

Commit this. Update `embeddedPublicKeyIsThePinnedProductionKey` in
`Tests/EntitlementsTests.swift` in the same change, and keep
`embeddedVerifierRejectsForeignTokens` proving a foreign key cannot unlock PRO.

## Step 3 — Inject the PRIVATE key at build time (release machine only)

The private key rides into the official binary via the same env-var pattern as the entitlements
(`Makefile` → `project.yml` → Info.plist `VitrineLicenseSigningKey` → `LicenseSigningKey.embedded`).
On the **release machine only**, before building the DMG:

```sh
export VITRINE_LICENSE_SIGNING_KEY="<YOUR PRIVATE BASE64>"
scripts/build-dmg.sh
```

Any build without that variable set (CI, a contributor's checkout, `make build`) leaves it empty,
so `LicenseSigningKey.embedded == nil` and the build stays free. The value is never written to the
repo. Tip: keep it in your login Keychain and export it in the build step, e.g.
`export VITRINE_LICENSE_SIGNING_KEY="$(security find-generic-password -s vitrine-license-key -w)"`.

## Step 4 — Lemon Squeezy product + license keys

1. Create a **product** "Vitrine PRO", one-time payment, **$19** (early-bird) → settle at $25.
2. Enable **license keys** for the product. Set the **activation limit** (e.g. 3 machines per
   license) — the app sends an `instance_name` (the Mac's name) so a buyer can see/manage seats.
3. No API key is embedded in the app: activation uses only the buyer's license key against the
   public `…/v1/licenses/activate` endpoint, which `LemonSqueezyValidator` already calls.
4. (Optional, later) Wire a lenient periodic re-validation / a deactivate action using the
   `instance.id` the activation returns (carried in `LicenseActivation.instanceID`).

## Step 5 — Verify

- **Local, before real keys (anyone):** run a DEBUG build with `VITRINE_PRO_UNLOCK=1` — unlocks
  the app (`DebugUnlockProvider`) and the CLI (`CLIEntitlement`) for manual QA. This path is
  compiled out of Release.
- **Real flow (after Steps 1–4):** build the DMG with the private key exported, run it, paste a
  real license key into the paywall's license field, and confirm PRO unlocks. Then run the bundled
  `vitrine render … ` — it should be unlocked too, because the app wrote the signed token to the
  shared file the CLI reads:
  `~/Library/Containers/com.johnny4young.vitrine/Data/Library/Application Support/Vitrine/pro-license.token`.

## Security notes

- The private key is **in the distributed binary** (Architecture B). For the honor model that is
  acceptable — a determined user can extract it, the same way they could fork the open-source app.
  It is not a DRM boundary; it is a convenience + an offline-trust mechanism for the CLI.
- The signed token is stored device-only in the Keychain (`kSecAttrAccessibleAfterFirstUnlock…
  ThisDeviceOnly`) and mirrored to a `0600` file. Neither is anti-copy; both raise seat-sharing
  above trivial.
- Rotating the keypair invalidates every issued token (they were signed by the old private key):
  only do it deliberately, and re-issue.

## What is already done (no action needed)

- `LicenseActivationService` + `LemonSqueezyValidator` (the online check + local mint).
- `LicenseSigningKey` (build-time private-key injection; nil ⇒ free).
- `LicenseKeyProvider.setToken` persists to Keychain **and** writes the CLI token file.
- `CLIEntitlement` reads that file from the app's container path and verifies offline.
- `Entitlements.activate(licenseKey:)` wires the paywall's license field to all of the above.
- Full unit + E2E tests (`Tests/LicenseActivationTests.swift`) using a development keypair.
