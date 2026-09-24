# Product capabilities and boundaries

This is a **reference**, not a release announcement. It describes the intended
integrated product contract; a feature in an open pull request is not available
in a published download until that change is integrated and released. Check the
[latest published release](https://github.com/johnny4young/vitrine/releases/latest)
for what you can install today. Source version numbers do not prove publication.

Vitrine is one native macOS product with two distribution channels. Both use the
same local rendering engine. "Free" means the indefinitely usable core, not a
time-limited trial; there is no watermark or resolution cap on normal single-image
export. PRO adds specific workflows, not a different rendering engine.

## Channels and entitlement

| Capability | Direct download / Homebrew | Mac App Store |
| --- | --- | --- |
| Editor, menu-bar capture, code/terminal/imported-image/HTML and social-card rendering | Free | Free |
| Single-image copy, save, and Share Sheet | Free | Free |
| Recents and comparison boards | Free; history can be disabled | Free; history can be disabled |
| Requested webpage URL capture and opt-in logged-in WebKit session | Available after disclosure | Not available: no network-client entitlement |
| Basic `vgrab` terminal capture | Free CLI | No bundled CLI |
| `vitrine render INPUT --edit` | Free **editor handoff only**; does not render, save, or copy | No bundled CLI |
| General CLI rendering, multi-size, batch, and `vpane` | PRO | No bundled CLI |
| Shortcuts: Open Code in Editor | Free handoff | Free handoff |
| Shortcuts: Render Code Image; macOS Service image rendering | PRO | PRO |
| Brand Kit, carousel, multi-size export, advanced frames, and rendering automation | PRO | PRO where the in-app surface exists |
| PRO purchase or activation | Honor-based direct license, activated with the provider; later verification is local | StoreKit purchase and Restore |
| Updates | Signed Sparkle feed | App Store |

macOS Services and App Intents obey their effective action's entitlement. An
editor-opening handoff does not silently acquire a PRO render capability. A
direct-download license is not an App Store purchase, and the CLI cannot infer a
StoreKit entitlement from a separate app process. The paywall appears only when
a gated action is attempted and must always offer a way back.

The [PRO architecture](PRO.md) defines individual gates. The
[permission matrix](PERMISSIONS.md) records build-time entitlements; the
[release process](RELEASING.md) records what must be verified before publishing.

## Privacy and retention

- Code, terminal, imported-image, pasted-HTML, and social-card rendering happens
  on the Mac. Vitrine has no account requirement, analytics, telemetry, Screen
  Recording permission, or Accessibility-control permission.
- Direct-download network access is limited to user-requested webpage/remote
  image input, updates, and license activation. A webpage is fetched by WebKit
  **on this Mac**; "local rendering" does not mean the requested website receives
  no request. App Store builds do not carry the network-client entitlement.
- Web capture checks the initial URL, redirects, and literal private subresource
  hosts; bounded downloads and non-persistent sessions are the default. These
  controls are **not DNS isolation**: a public host that resolves or rebinds to a
  private address remains a residual risk. Authenticated browsing is opt-in,
  visible, and clearable.
- Explicitly redacted source is never retained as an original in Recents. If a
  heuristic secret scan detects possible sensitive content, automatic history
  storage is deferred for that capture: dismissing the choice means **do not
  save**; the user can choose a sanitized record or consciously keep the
  original. That choice does not silently change an export they requested and
  is not remembered for later captures. The scanner can miss secrets; always
  inspect an image before sharing it.
- History can be disabled without deleting existing records. Removing old
  history and cached previews is a separate explicit action; it does not claim
  to erase system backups. Comparison-board drafts hold finished pixels and
  visible captions only while open.
- Cooperative clipboard privacy metadata is optional and off by default. Other
  applications may ignore it; it is not a universal confidentiality guarantee.

For implementation details, see [rendering](RENDERING.md),
[architecture](ARCHITECTURE.md), and [permissions](PERMISSIONS.md).

## Ownership and release boundary

Domain owns pure content rules and models; Rendering owns deterministic
composition and encoding; the app owns Keychain, purchases, WebKit and UI
lifecycle. The CLI reuses pure rendering code but owns no network transport.
The Xcode project is generated from `project.yml`, not edited in Xcode's
generated project file. A source build, green unit suite, or marketing-site
change is not a signed release. Both channels need their own optimized
universal build, UI and privacy acceptance, exact-head checks, and the
channel-specific release procedure before publication.

Start with the [synthetic first-capture tutorial](FIRST-CAPTURE.md); consult
[Help](HELP.md) for tasks after the first image.
