# ADR 0002: Keep Vitrine in Swift; Rust only on demand

- **Status:** Accepted
- **Date:** 2026-11-05
- **Review when:** users ask for Vitrine outside the Mac

## Context

In November 2026 the maintainer reviewed the stack of every app, comparing SwiftUI and
Electron with Go (Fyne, Wails) and Rust (Tauri, GPUI). The same small app was built in all
six and measured on Apple silicon. No stack used less memory than SwiftUI. Webview shells
saved bundle size but not memory or startup, and GPUI was the only one close to SwiftUI on
memory, at the cost of rewriting the UI. Nothing was measured on Windows, on Linux or in
Vitrine itself.

## Decision

The Mac app, its UI and the `vitrine` CLI stay in Swift. A Rust port of the renderer or
CLI starts only when users ask for Vitrine on another platform.

## Consequences

- No Rust code or cross-platform layer lands before that demand.
- If GPUI is chosen then, the license rule in `AGENTS.md` keeps Zed's GPL crates out.
- The measurements are in the maintainer's private research report, not in this
  repository.
