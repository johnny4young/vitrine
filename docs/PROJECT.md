# Vitrine — Project Overview

Vitrine is an open-source macOS menu-bar app for turning code, terminal output,
web content, social cards, and imported images into polished, reproducible assets.
It is native, fast, and local-first: the render core does not depend on a hosted
service, an account, analytics, or telemetry.

This document records the product that exists today. Release history belongs in
[`CHANGELOG.md`](../CHANGELOG.md); implementation details belong in
[`ARCHITECTURE.md`](ARCHITECTURE.md); maintainer planning is intentionally not part
of the published repository.

## Product position

Vitrine competes with browser-based code-image tools by removing the browser and
keeping the workflow close to the clipboard, menu bar, editor, command line, and
macOS automation surfaces. The differentiators are:

- native macOS interaction and startup behavior;
- deterministic, reusable rendering across the app, CLI, Shortcuts, Services, and
  App Intents;
- code, terminal, web, social-card, and imported-image inputs in one pipeline;
- on-device privacy features such as secret detection, OCR, and redaction;
- reproducible visual fixtures and performance budgets;
- no mandatory account, subscription, or cloud renderer.

The product is intentionally not a general-purpose screen recorder, a cloud-first
design suite, or a cross-platform shell. See [`SCREEN-CAPTURE.md`](SCREEN-CAPTURE.md)
for the decision to avoid arbitrary display and window capture.

## Technology

- Swift 6.2, SwiftUI, and focused AppKit integration
- XcodeGen, with `project.yml` as the project source of truth
- Highlightr for syntax highlighting
- WebKit for local HTML and user-requested webpage rendering
- Vision for on-device OCR
- ImageRenderer and ImageIO for color-managed raster export
- Swift Testing and XCTest UI automation

The deployment floor is macOS 14. Newer APIs may be adopted behind availability
checks when they add meaningful value without fragmenting the codebase.

## Distribution and business model

The source and free product are MIT-licensed. Signed, notarized releases are
available from GitHub and through the Homebrew cask. The same app can also be built
for App Store distribution.

An optional one-time PRO purchase funds development. PRO adds Brand Kit,
multi-size export, carousel workflows, and automation-oriented capabilities. The
render core and normal editing workflow remain available without PRO. StoreKit is
used for the App Store channel; the direct-download channel verifies signed license
data locally. See [`PRO.md`](PRO.md) and [`ACTIVATION.md`](ACTIVATION.md).

## Privacy and permissions

Vitrine renders user content on the Mac; normal editing content never leaves the
Mac. It has no analytics SDK and sends no telemetry. The App Store build does not
request the `com.apple.security.network.client` entitlement. The signed
direct-download build has that narrowly documented entitlement for Sparkle,
explicit webpage capture, and user-requested remote image import.

URL and HTML snapshots are rendered locally in WebKit, with no remote screenshot
service. Only
explicit `http` and `https` inputs are accepted for remote capture, local and
private destinations are rejected, redirects are revalidated, and website data is
non-persistent unless the user explicitly chooses a logged-in session.

The app does not request Screen Recording or Accessibility permission. User-selected
file access, clipboard behavior, channel-specific entitlements, and their App Store
impact are documented in [`PERMISSIONS.md`](PERMISSIONS.md).

The privacy manifest declares no tracking and no collected data; the App Store
privacy label is **Data Not Collected**. Its only required-reason API category is
UserDefaults, used for the app's own settings.

## Quality contract

Every release is expected to preserve:

- one render contract shared by all entry points;
- strict input validation and bounded decoding, downloads, and caches;
- deterministic golden-image coverage for supported rendering surfaces;
- accessibility labels, keyboard access, and complete English and Spanish strings;
- a generated project that builds from a clean checkout;
- signed release artifacts whose version, notes, cask, and update feed agree.

The exact release process is in [`RELEASING.md`](RELEASING.md). Publicly shipped
behavior is summarized in [`README.md`](../README.md) and versioned in
[`CHANGELOG.md`](../CHANGELOG.md).
