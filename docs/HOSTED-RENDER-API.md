# Hosted render API — design record (CS-080, ⏸ Future)

> **Status: parked.** This is the design that must exist *before* CS-080 is un-parked, per
> the roadmap's "acceptance before un-parking." It is a decision/architecture record, **not**
> an implementation. No hosted service code lives in this repository, and the native macOS
> app must never depend on one.

## Why this is parked

Vitrine's reason for being is a **native, instant, fully local** menu-bar app. A hosted
render API serves a *different* audience — non-Mac clients and programmatic/CI callers that
want "code → image" or "URL → image" over HTTP. That audience does not exist yet, and
building a server now would add a large security/operations surface for no current user.

So CS-080 stays parked until **all** of these hold:

1. A concrete user segment exists *beyond* the native app (e.g. a documented set of CI/web
   callers asking for it).
2. The security/abuse design below is implemented and reviewed.
3. **The native app remains 100% functional with the service offline** — the service is an
   optional add-on, never a dependency of the app's renderer.

## Non-negotiable boundary

```
Vitrine.app (this repo)            hosted-render-api (separate repo, separate stack)
  └── ExportManager/ImageRenderer    └── HTTP API → renderer workers
  └── 100% local, no network         └── Satori/Resvg (templates) + gated Playwright (URLs)
         ▲                                   │
         └──────────── NEVER depends on ─────┘
```

The app's local render path (CS-005/007, CS-040–044) is the source of truth. The hosted API
is a **second, independent** implementation for non-Mac callers; it may *reuse the template
designs* but shares no runtime with the app and lives in its own repository.

## Proposed architecture (separate repo, not Swift)

| Concern | Choice | Rationale |
| --- | --- | --- |
| Code/template → image | **Satori + Resvg** (or `resvg-js`) | Deterministic, sandbox-free, no browser needed for controlled templates (the social-card / code-card layouts). |
| URL → image | **Playwright**, gated | Only for the explicit URL-capture job class; never the default path. |
| Runtime | Stateless workers behind a queue | Horizontal scale; a hung browser job can't take down the API. |
| API shape | `POST /v1/render` → signed artifact URL | Async for URL jobs; sync for template jobs. |

## Mandatory security/abuse controls (gates before launch)

These are **required** before any URL-capturing endpoint ships:

- **SSRF guard** — deny private/link-local/loopback/metadata ranges (`169.254.0.0/16`,
  `10/8`, `127/8`, `::1`, cloud metadata `169.254.169.254`), resolve-then-pin the IP, block
  redirects that escape the allowlist, scheme allowlist `http`/`https` only.
- **Browser isolation** — each Playwright job in a locked-down, ephemeral sandbox
  (no shared profile, `--no-sandbox` forbidden, seccomp/AppArmor, egress-filtered network),
  killed after a hard timeout and memory cap.
- **Rate limits & quotas** — per-key and per-IP; backpressure via the queue.
- **Retention limits** — rendered artifacts auto-expire; no indefinite storage of user URLs
  or images.
- **Signed artifact URLs** — time-limited, unguessable; no public listing.
- **Abuse controls** — key revocation, anomaly alerts, and a kill switch for the URL path.
- **Privacy** — log no full URLs or image bytes; document exactly what is retained and for
  how long; the service has its **own** privacy policy distinct from the app's local promise.

## Billing / operations (gates)

- A funding model (the service has real per-render cost: CPU, browser RAM, egress).
- Observability: per-job tracing, queue depth, browser-crash rate, SSRF-deny counters.

## What "starting" this ticket means here

This document. No service code. When the un-parking criteria above are met, CS-080 graduates
to its own repository with its own roadmap; this file becomes the seed of that repo's design.
