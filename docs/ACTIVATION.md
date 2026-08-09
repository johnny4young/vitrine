# PRO activation — direct-download (Lemon Squeezy) runbook

How to operate and certify real PRO activation for the **direct-download / Homebrew (DMG)**
build. The checkout URL, release-secret injection, pinned product identity, online activation,
and offline token path are implemented. They are not self-certifying: every release still needs
the published-artifact journey below. The Mac App Store channel is separate — see
[APP-STORE.md](APP-STORE.md).

## How it works (the official app signs locally)

```
user pastes license key
   → LicenseActivationService validates it once online (Lemon Squeezy /v1/licenses/activate)
     and requires the pinned Vitrine store/product identity plus a live, active license
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

- The live Vitrine PRO Lemon Squeezy product with license keys enabled and a dedicated live QA
  license whose activation seat can be reset between release checks.
- This repo, able to build the DMG (`scripts/build-dmg.sh`).
- A clean compatible Mac for the published-DMG certification. Do not certify from DerivedData.

## Step 1 — Generate a signing keypair (first setup or deliberate rotation only)

```sh
swift scripts/generate-license-keypair.swift
```

It prints a **PUBLIC** and a **PRIVATE** base64 value. They are a pair: a token signed with
PRIVATE verifies only against PUBLIC. Keep the PRIVATE value secret (your Keychain or a password
manager). **Never commit it.**

## Step 2 — Pin the public key and product identity (source — not secret)

In [`Vitrine/Pro/LicenseKey.swift`](../Vitrine/Pro/LicenseKey.swift), confirm
`LicensePublicKeys.productionBase64` matches the generated public key. If rotating, replace that
literal and update `embeddedPublicKeyIsThePinnedProductionKey` in
`Tests/EntitlementsTests.swift` in the same change. Keep
`embeddedVerifierRejectsForeignTokens` proving a foreign signer cannot unlock PRO.

In [`Vitrine/Pro/LicenseActivation.swift`](../Vitrine/Pro/LicenseActivation.swift), keep
`LemonSqueezyValidator.expectedStoreID` and `expectedProductID` aligned with the live public
checkout. These public numeric identifiers prevent a valid license for another Lemon Squeezy
product from minting a Vitrine token. A price change within the same product does not require an
app update; replacing the product does.

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

## Step 4 — Lemon Squeezy product contract

1. Keep **Vitrine PRO** a one-time product. The website currently advertises **$19.99** during
   the 2026 launch period and a planned **$25** regular price; the public checkout must agree
   before either claim changes.
2. Enable **license keys** for the product. Set the **activation limit** (e.g. 3 machines per
   license) — the app sends an `instance_name` (the Mac's name) so a buyer can see/manage seats.
3. No API key is embedded in the app: activation uses only the buyer's license key against the
   public `…/v1/licenses/activate` endpoint, which `LemonSqueezyValidator` already calls.
4. Production activation accepts only the pinned Vitrine store/product, an active status, a
   traceable license id, and a non-test-mode key. Any missing or foreign identity fails closed.

## Step 5 — Certify the published direct-download artifact

- **Local, before real keys (anyone):** run a DEBUG build with `VITRINE_PRO_UNLOCK=1` — unlocks
  the app (`DebugUnlockProvider`) and the CLI (`CLIEntitlement`) for manual QA. This path is
  compiled out of Release and does **not** certify production activation.
- **Automated artifact gate:** run `scripts/qa-release.sh` against the downloaded, published DMG.
  It validates signing/notarization and confirms that `VitrineLicenseSigningKey` exists and
  decodes to exactly 32 bytes without printing the private value. A structural pass proves only
  that the app can attempt to mint; it does not prove the live provider journey.
- **Online activation:** install that DMG on a clean Mac, open a PRO-gated action, paste the
  dedicated **live** QA license into the masked field, and activate. Confirm the paywall closes
  and a PRO-only multi-size export succeeds. Never record the raw license key in screenshots,
  shell history, logs, issue text, or the QA record.
- **Offline relaunch:** quit the app, disconnect every network interface, relaunch, and repeat a
  PRO-only action. This proves the Keychain-backed token works without Lemon Squeezy.
- **CLI handoff:** while still offline, exercise a capability that remains PRO even if basic
  terminal capture becomes free:

  ```sh
  printf 'let releaseQA = true\n' > /tmp/vitrine-pro-qa.swift
  /Applications/Vitrine.app/Contents/MacOS/vitrine-cli \
    multi-size /tmp/vitrine-pro-qa.swift --out /tmp/vitrine-pro-qa-cards \
    --presets twitter,opengraph
  test -s /tmp/vitrine-pro-qa-cards/vitrine-twitter.png
  test -s /tmp/vitrine-pro-qa-cards/vitrine-opengraph.png
  ```

- **Token mirror:** prove presence and permissions without reading or printing the token:

  ```sh
  token="$HOME/Library/Containers/com.johnny4young.vitrine/Data/Library/Application Support/Vitrine/pro-license.token"
  test -s "$token"
  test "$(stat -f '%Lp' "$token")" = "600"
  ```

Record the app/build version, macOS version, architecture, dedicated QA license label or a
redacted order/license identifier, and pass/fail for every step. **Never record** the license
key, embedded private signing key, or token contents. Before the first public sale — and whenever
checkout, pricing, email fulfillment, or Lemon Squeezy product configuration changes — also
complete a production-mode checkout from the public website and confirm the license email
arrives before using that key for the same journey.

### Current lifecycle boundary

The direct-download v1 UI has no Restore or Deactivate action, and the locally minted token does
not retain `instanceID`. Upgrades and offline relaunches preserve the entitlement. A clean Mac
must activate the license again; remote seat removal and refund revocation are not implemented.
Do not mark those nonexistent flows as tested or promise them in support copy. Designing them
requires retaining the instance id and license credential securely, then validating/deactivating
against Lemon Squeezy without weakening the offline-first honor model.

## Security notes

- The private key is **in the distributed binary** (embedded-key activation model). For the honor model that is
  acceptable — a determined user can extract it, the same way they could fork the open-source app.
  It is not a DRM boundary; it is a convenience + an offline-trust mechanism for the CLI.
- The signed token is stored device-only in the Keychain (`kSecAttrAccessibleAfterFirstUnlock…
  ThisDeviceOnly`) and mirrored to a `0600` file. Neither is anti-copy; both raise seat-sharing
  above trivial.
- Rotating the keypair invalidates every issued token (they were signed by the old private key):
  only do it deliberately, and re-issue.

## What is already done (no action needed)

- `LicenseActivationService` + `LemonSqueezyValidator` (the online check + local mint).
- Pinned Lemon Squeezy store/product validation, including rejection of foreign and test keys.
- `LicenseSigningKey` (build-time private-key injection; nil ⇒ free).
- `LicenseKeyProvider.setToken` persists to Keychain **and** writes the CLI token file.
- `CLIEntitlement` reads that file from the app's container path and verifies offline.
- `Entitlements.activate(licenseKey:)` wires the paywall's license field to all of the above.
- Full unit + E2E tests (`Tests/LicenseActivationTests.swift`) using a development keypair.
- Published-artifact structural QA plus a secret-safe manual activation checklist.
