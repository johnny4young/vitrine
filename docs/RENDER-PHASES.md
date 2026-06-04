# Beyond Code — Render, OG & Screenshots

> This section consolidates **inside Vitrine the capability that used to be the
> separate "ShotAPI" project** — one project, not two. The re-analyzed question: is it
> done in the Apple ecosystem (Swift) or does it need a web integration?

**Key insight:** Vitrine's engine (SwiftUI → `ImageRenderer` → PNG) is not tied to
code — it is a *view-to-image renderer*. Generalizing it to **OG / social cards** and
even **HTML / URL snapshots** is natural and **100% Apple-native, serverless**.

> The Apple-native renderer (code → image via `ImageRenderer`; URL/HTML → snapshot via
> `WKWebView`) is the same engine as the quick mode. Quick mode just invokes it with
> your saved settings.

## What each capability needs

| Capability                                   | Apple-native (local, inside Vitrine)            | Needs a server?                        |
| -------------------------------------------- | ----------------------------------------------- | -------------------------------------- |
| Code → image                                 | SwiftUI + Highlightr + `ImageRenderer`          | No                                     |
| OG cards / social templates (text + layout)  | SwiftUI views + `ImageRenderer` (1200×630)      | No — a trivial extension              |
| HTML/CSS → image                             | `WKWebView.takeSnapshot` / `createPDF`          | No (local, offscreen `WKWebView`)     |
| Screenshot of an arbitrary URL               | `WKWebView` load + snapshot                      | No (local, on a Mac)                   |
| **Programmatic HTTP API for other stacks**   | — a desktop app is not an API                   | **Yes → web service**                 |
| Hosted, scalable, cross-platform render      | SwiftUI / WKWebView don't exist on Linux        | **Yes → Node + Satori/Playwright**    |

## Options (Apple first, web as fallback)

**A · Apple-native, local — RECOMMENDED for the core and v1–v2.** Everything the app
needs is done in Swift, locally, with no infra: code images, OG/social cards (same
`ImageRenderer` pipeline) and even HTML/URL snapshots via `WKWebView`. Fits OSS +
unmonetized + Apple ecosystem perfectly. *Caveat:* offscreen rendering with
`WKWebView` requires sizing the view and, in some cases, attaching it to a hidden
window before `takeSnapshot`.

**B · Swift-on-server (Vapor/Hummingbird) — DISCARDED for rendering.** Swift runs on
Linux, but `SwiftUI`, `ImageRenderer`, `WKWebView`, and AppKit **do not exist on
Linux**. A Vapor app on Linux cannot render the views; on macOS it can, but hosting
macOS is expensive and impractical. Swift-server is not the path to *generate* images.

**C · Web integration (Node + Satori / Playwright) — FALLBACK, only if an API/hosting
is actually needed.** The only thing that justifies leaving Apple-native: exposing the
render as an **HTTP API for other stacks**, **public-URL sharing**, or non-Apple
consumers. Satori (HTML/CSS subset → SVG → PNG, no browser) for OG/templates;
Playwright for arbitrary screenshots. Inherits all of the ShotAPI research (SSRF
guard, cache key, R2/CDN) — now as **Phase C of Vitrine**, not a separate project.

**Recommendation:** stay Apple-native (A) for the core and most of OG/screenshots;
keep the web (C) as a well-bounded optional phase, never a dependency of the core.

---

## Reference — web render stack (Phase C, optional)

> Inherited from the former **"ShotAPI — Screenshot & OG Images"** project (research
> 2026-04-24). No longer a separate project: this is reference material for **Phase C**
> of Vitrine, if a web surface is ever built (programmatic API or public-URL sharing).
> The Apple-native core **does not depend** on any of this.

**What it was:** a developer-first API to generate Open Graph images, HTML-to-image,
thumbnails, and URL screenshots. After market research the recommendation was to treat
it as **two lines**, not one generic endpoint:

1. **OG / HTML-to-image without a browser** — 1200×630 templates, social cards, visual
   receipts. Rendered with **Satori + Resvg/Sharp**. Cheap, fast, deterministic, low
   risk. The proposed MVP.
2. **Arbitrary screenshots with a browser** — any URL, full-page, PDF, dark mode,
   custom viewport with **Playwright**. Sells well, but brings SSRF, abuse, anti-bot,
   high RAM/CPU, queues, and heavy support. A later phase, closed beta.

**Defensible wedge:** OG image automation for non-Vercel stacks (Rails, Laravel,
Django, WordPress, Ghost, Astro) + ready-made templates + storage/CDN + DX (curl, TS
SDK, playground) + LatAm latency as a plus.

**API modes:** `POST /v1/og` (templates, MVP), `POST /v1/html-image` (controlled
HTML/CSS), `POST /v1/screenshot` (arbitrary URLs, gated behind an SSRF checklist).

**Mandatory security (if ever built):** SSRF guard (http/https only, block
private/loopback/link-local/cloud-metadata IPs, don't follow redirects without
re-validation, block `file`/`gopher`/`data`), browser sandbox (never root, no
`--no-sandbox` for third parties, clean context per job, hard timeouts), short
retention + signed URLs + HMAC webhooks.

**Proposed architecture:** Hono (Node.js + TS, Fly.io) · Satori in-process for `/og` ·
isolated Playwright workers · deterministic cache key (`mode + payload +
template_version + renderer_version + asset_hashes + format + dims`) · R2 + CDN for
artifacts · Postgres (users, usage, billing) + Redis (cache/rate-limit).

**Naming risk:** strong collision — `shotapi.io/.dev/.com/.net` are already screenshot
products. "ShotAPI" was only a working title; it would need a rebrand.

**Sources consulted:** ScreenshotOne pricing · URLbox · Browserless · HTML/CSS to
Image · Vercel OG · Satori · Playwright Docker · OWASP SSRF Cheat Sheet · Cloudflare R2
pricing · Fly.io pricing.
