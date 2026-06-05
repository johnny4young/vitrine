# Arbitrary screen / window capture — discovery (CS-046)

> Decision document for whether Vitrine should ever capture arbitrary windows or
> display regions (a live screenshot of *the screen*, not a view Vitrine renders
> itself). This is a 🟡 Discovery spike: it produces a recommendation and the safe
> guardrails, **not** a shipped capture feature. No screen-capture code is added to the
> app target by this ticket.

## TL;DR — recommendation

**Park it (⏸ Future), do not promote to Product Phase 2.x.** Arbitrary screen/window
capture is a *different product* with a *different permission profile* from everything
Vitrine ships today. Vitrine's entire identity is "Vitrine renders its own pixels": the
code canvas (`ImageRenderer`) and the deferred URL/HTML path (`WKWebView`) both produce
images from content Vitrine itself draws, with **no Screen Recording permission and no
network egress of your screen**. Capturing the *real desktop* breaks that promise: it
requires the system Screen Recording permission (TCC), can pull in any other app's
window or private on-screen data, and pushes Vitrine into the crowded "screenshot
utility" category where macOS already ships a capable built-in tool. The upside (a
beautify-my-existing-screenshot flow) is real but is **better served by a passive
"decorate an image the user already captured" path**, which needs *zero* new permissions
and reuses the existing canvas. See [Safe alternative](#safe-alternative-the-non-go-go).

This decision is recorded in `docs/ROADMAP.md` under CS-046 (status flipped from
🟡 Discovery to ⏸ Future) and is consistent with the permission matrix planned in CS-065,
which already states that any arbitrary screen/window capture "must stay out of core
until approved."

## What this is — and what it is not

| | Renders its own pixels (today) | Arbitrary screen/window capture (this doc) |
| --- | --- | --- |
| Code → image | `SwiftUI` + Highlightr → `ImageRenderer` → PNG/PDF. Local, deterministic. | — |
| URL/HTML → image (Phase 2, deferred) | `WKWebView` loads the page **locally** and rasterizes on-device. | — |
| Source of pixels | Content Vitrine draws or loads into its own offscreen views. | **Other apps' windows / the live display**, owned by other processes or the system. |
| Permission needed | Clipboard read, user-selected file save. **No** Screen Recording. | **Screen Recording** (TCC: *Screen & System Audio Recording* on macOS 15+). |
| Privacy posture | Nothing leaves the Mac; nothing private is implicitly in frame. | Can implicitly capture passwords, messages, other users' content on screen. |
| Product category | "Beautiful code screenshots" | "Screenshot utility" (competes with the OS and with CleanShot/Shottr/etc.) |

The distinction matters because the entitlement and trust cost is paid the moment the
*capability* exists, not the moment a user first uses it. Shipping a Screen Recording
code path changes Vitrine's App Store privacy posture, its TCC prompt surface, and its
security-review story even if 99% of users never invoke it.

## Option A — ScreenCaptureKit (the modern API, if we ever build this)

[`ScreenCaptureKit`](https://developer.apple.com/documentation/screencapturekit) (macOS
12.3+) is the current, non-deprecated framework for capturing displays, individual
windows, or a single application's output. It is what we would use if this ticket were
ever promoted; the legacy paths below are explicitly *not* candidates.

**How it would work**

- `SCShareableContent.current` (async) enumerates `displays`, `windows`, and
  `applications`. The app uses this to let the user pick *what* to capture.
- For a **one-shot still**, `SCScreenshotManager.captureImage(contentFilter:configuration:)`
  (macOS 14+) returns a `CGImage` for a built `SCContentFilter` — no stream lifecycle to
  manage. This is the right primitive for a screenshot tool; we would not stand up an
  `SCStream` for a single frame.
- An `SCContentFilter` can scope capture to a single window, a single display, or one
  application, and can exclude windows — useful to keep Vitrine's own UI out of frame.
- The captured `CGImage` would flow straight into the existing canvas (place it on the
  branded background, add the window chrome, export through the same
  clipboard/file/PDF/share pipeline).

**Permission**

- Requires the **Screen Recording** entitlement/permission. On macOS 15 (Sequoia) and
  later this appears to users as **"Screen & System Audio Recording"** in System
  Settings → Privacy & Security, and the system shows a recurring/periodic re-consent
  prompt for apps that hold it. The first capture triggers a TCC prompt; denial cannot be
  worked around, and there is no silent fallback.
- Under App Sandbox the app must still pass the TCC check at runtime; the permission is a
  *user* grant, not just an entitlement. `SCShareableContent` returns nothing capturable
  until the user has granted it, so the UX must handle the "not yet granted / denied"
  state as a first-class flow, not an error.

**Pros**

- Modern, supported, GPU-efficient; the same framework Apple steers all capture toward.
- Fine-grained scoping (single window / single app) and the ability to exclude Vitrine's
  own windows.
- `SCScreenshotManager` gives a clean still-image path without stream plumbing.

**Cons**

- Carries the full Screen Recording permission cost and the recurring macOS 15 re-consent
  prompt — a heavy, recurring trust ask for a "make it pretty" feature.
- macOS 12.3+ (and `SCScreenshotManager` is 14+); fine for our floor (deployment target
  14.0) but it is still a large surface to own and test.
- Pulls Vitrine into "can see your whole screen" territory, which materially changes the
  security-review and App Store-review narrative.

## Option B — System Screenshot handoff (no in-app capture)

Instead of capturing pixels ourselves, hand the act of capturing to the OS / the user and
only *decorate* the result. Two concrete shapes:

1. **Passive decorate (recommended safe path — see below).** The user captures with the
   built-in macOS tool (`⌘⇧4` / `⌘⇧5`, which already supports window and region capture,
   annotation, and "show floating thumbnail"), then brings that image into Vitrine via
   clipboard, drag-and-drop, or file open. Vitrine never touches the live screen.
2. **Invoke the system UI from Vitrine (still not us capturing).** Historically apps
   shelled out to the `screencapture` command-line tool, e.g. `screencapture -i -c` for
   interactive region/window capture to the clipboard. **This is a no-go for the shipped
   target:** under App Sandbox we cannot spawn arbitrary helper processes, the launched
   capture is still gated by the *same* Screen Recording TCC grant (the OS attributes it
   to the calling app), and driving it cleanly from a sandboxed menu-bar app is fragile.
   It buys none of the privacy benefit of path 1 while adding sandbox and reliability
   problems.

**Permission**

- Path 1 needs **no new permission at all** — the OS already holds the user's consent for
  its own capture tool; Vitrine only receives a finished image (same as pasting any
  screenshot today).
- Path 2 still requires Screen Recording and is incompatible with the sandbox, so it is
  rejected.

**Pros (path 1)**

- Zero new entitlements, zero TCC prompts from Vitrine, no change to the App Store privacy
  labels or `PrivacyInfo.xcprivacy`.
- Reuses the macOS capture UX users already know (region/window picker, instant markup).
- Delivers the actual user value ("my screenshot, but beautiful") with none of the risk.

**Cons (path 1)**

- One extra user step (capture, then bring into Vitrine) versus an all-in-one capture
  button.
- We do not control the capture moment, so we cannot, e.g., auto-exclude a specific window
  — but for a beautifier that is acceptable.

## Option C — No-go / rejected paths

- **`CGWindowListCreateImage` / `CGDisplayCreateImage`** — the pre-SCK Quartz capture
  APIs. **Deprecated** in recent macOS and superseded by ScreenCaptureKit; using them
  would violate the project's "no legacy/deprecated APIs" rule (AGENTS.md). Rejected
  outright.
- **AVFoundation `AVCaptureScreenInput`** — built for screen *recording* (video), not a
  single still, and still requires Screen Recording. Wrong tool, same permission cost.
- **Accessibility (`AXUIElement`) tricks to read window contents** — not a capture API,
  abuses the Accessibility permission, brittle, and an even worse trust ask than Screen
  Recording. Rejected.
- **A hosted / remote capture service** — sending the user's screen off-device to be
  rasterized. Directly contradicts Vitrine's core privacy promise (`docs/PROJECT.md`,
  `README.md`). This is the *opposite* of what Vitrine is. Rejected, and would remain
  rejected even in Product Phase 3 (which is for programmatic API render of *controlled*
  templates, never the user's live screen).

## Permission, App Store, and user-trust impact

This is the crux of the discovery and the reason for the recommendation.

- **Required user permission.** Any first-party capture of arbitrary windows/displays
  requires **Screen Recording** — surfaced on macOS 15+ as **"Screen & System Audio
  Recording"** — granted per-user via a TCC prompt on first use, and re-confirmed
  periodically by recent macOS. An `Info.plist` usage string and an in-app first-use
  explanation would be mandatory, and the app must degrade gracefully when the grant is
  denied or revoked. This is the heaviest privacy-sensitive permission Vitrine could ask
  for, far above clipboard or user-selected file access.
- **App Store / review risk.** Screen Recording capability changes the App Store privacy
  posture: reviewers expect a clear, demonstrable reason for an app to see the whole
  screen, and a "beautify screenshots" justification invites scrutiny and possible
  rejection or extra review notes. It would also force an update to
  `Vitrine/Resources/PrivacyInfo.xcprivacy`, the App Store privacy labels, the entitlement
  set (CS-062), and the permission matrix (CS-065). None of that is justified by the
  feature's value.
- **User-trust impact.** Vitrine's entire pitch is "your code never leaves your Mac" and
  "no elevated permissions." A menu-bar app that *can* record the screen reads very
  differently to a privacy-conscious developer — it is exactly the kind of capability that
  makes people audit a tool. Holding the permission at all (even unused) erodes the "needs
  no Screen Recording" line that the README and PROJECT docs currently make, and that the
  Phase 1 entitlement comment guarantees.
- **Sandbox interaction.** The app is sandboxed. Screen Recording is a runtime TCC grant
  layered on top of the sandbox; it does not relax the sandbox but does add a prompt
  surface and a revocable state the UI must handle. The system-handoff alternative avoids
  this entirely.

## Safe alternative — the non-go-go

The legitimate user need behind this ticket is **"make a screenshot I already have look as
nice as my code screenshots."** That is fully serviceable today with **no new permission**:

- **Passive image decoration.** Accept an existing image (clipboard paste, drag-and-drop,
  or file open via the existing user-selected file entitlement), drop it onto the same
  branded background + window-chrome canvas, and export through the existing
  clipboard/file/PDF/share pipeline. The OS (or the user's existing capture tool) does the
  capturing; Vitrine only beautifies the result.
- **Zero permission delta.** No Screen Recording, no `PrivacyInfo.xcprivacy` change, no
  App Store posture change, no new TCC prompt. It is the same trust profile Vitrine
  already ships.
- **Out of scope for CS-046.** If this is wanted, it should be its own scoped backlog
  ticket ("decorate an imported screenshot/image on the canvas"), reusing the canvas and
  export modules — **not** a screen-capture ticket. This document recommends that route
  over arbitrary capture.

## Decision

- **Park CS-046 as ⏸ Future.** Do not promote arbitrary screen/window capture to Product
  Phase 2.x. The permission, privacy, App Store, and product-identity costs outweigh the
  benefit, and the real user value is reachable without any of them.
- **No code is added to the app target.** This ticket ships only this document and the
  ROADMAP status update. There is no ScreenCaptureKit dependency, no Screen Recording
  entitlement, no `Info.plist` usage string, and no capture UI. The Phase 1 promise
  ("needs no Screen Recording") stands.
- **If ever revived,** the only acceptable first-party implementation is **Option A
  (ScreenCaptureKit + `SCScreenshotManager`)** behind an explicit, separately-approved
  decision, with the full prototype validation checklist below satisfied first. The legacy
  Quartz/AVFoundation paths (Option C) remain permanently rejected.

## Prototype validation checklist (only if promoted)

If this is ever un-parked, a throwaway prototype **outside the shipped target** (a
separate scratch target or Swift package, never the `Vitrine` app target) must clear all of
the following before any approval to integrate:

- [ ] Uses `ScreenCaptureKit` only — no `CGWindowListCreateImage`, `CGDisplayCreateImage`,
      `AVCaptureScreenInput`, or Accessibility scraping.
- [ ] Enumerates shareable content via `SCShareableContent` and captures a single still via
      `SCScreenshotManager.captureImage(...)` (no `SCStream` for a one-shot).
- [ ] Triggers the Screen Recording (Screen & System Audio Recording) TCC prompt on first
      use and behaves correctly when the user **denies** and later **revokes** the grant.
- [ ] Can scope a capture to a single window / single display and can **exclude Vitrine's
      own windows** from the frame.
- [ ] Verified under App Sandbox (the prototype runs sandboxed and still obtains the grant
      at runtime).
- [ ] Produces a `CGImage` that feeds the existing canvas + export pipeline unchanged.
- [ ] Draft updates prepared for `PrivacyInfo.xcprivacy`, App Store privacy labels, the
      entitlement set (CS-062), the permission matrix (CS-065), and the README/PROJECT
      privacy copy — reviewed *before* any merge to the app target.
- [ ] An explicit product decision to accept the Screen Recording permission cost is
      recorded in `docs/ROADMAP.md` (flip ⏸ Future → 🔵 Backlog) before integration begins.

## References

- `docs/ROADMAP.md` — CS-046 (this ticket), CS-065 (permission matrix), CS-062 (App Store
  readiness), Product phase contract.
- `docs/PROJECT.md` — "Privacy and permissions" (the canonical per-phase posture).
- `docs/RENDER-PHASES.md` — why the renderer stays Apple-native and local.
- `Vitrine/Resources/Vitrine.entitlements` — the Phase 1 entitlement set this decision
  keeps intact.
- [Apple — ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple — `SCScreenshotManager`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)
