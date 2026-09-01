# ADR 0001: Retain the current syntax-highlighting engine

- **Status:** Accepted
- **Date:** 2026-09-01
- **Review when:** a candidate satisfies every compatibility and qualification gate below

## Context

Vitrine advertises 33 source languages, 13 built-in themes, and user-defined palettes.
The app and CLI must produce the same image through a synchronous SwiftUI `ImageRenderer`
pipeline, remain fully local, compile in Swift 6 mode, and preserve deterministic output.
The highlighting adapter also enforces the 128 KiB interactive tokenization ceiling and
bounded caches.

The current dependency, [Highlightr 2.3.0](https://github.com/raspu/Highlightr), wraps a
bundled Highlight.js runtime. Its maintainer declared the project no longer actively
maintained in 2026 and recommended
[HighlighterSwift](https://github.com/smittytone/HighlighterSwift) as a successor. That
maintenance transition warranted a measured replacement review rather than an automatic
package swap.

## Decision

Retain exact Highlightr 2.3.0 temporarily behind `VitrineRendering.HighlightManager`.
Do not expose Highlightr types outside that adapter. Every built-in stylesheet name must
exist in the engine catalog, and an unavailable stylesheet must fall back explicitly to
One Dark rather than inheriting the mutable engine's previously selected theme.

No evaluated replacement met the complete language, theme, visual-parity, performance,
memory, API-shape, and maintenance contract. Keeping the current engine is accepted
technical debt, not a claim that the dependency is healthy or current.

## Evidence

Measurements were collected on the same Apple silicon Mac, macOS 26.5.2, and Xcode 26.6.
The Vitrine performance suite is the product-level result; the isolated harness is a
directional comparison using the same 33 short fixtures and 30 iterations per process.

| Engine | Compatibility result | Product uncached-medium p95 | Isolated median time / peak RSS | Decision |
| --- | --- | ---: | ---: | --- |
| Highlightr 2.3.0 (`05e7fcc`) | Current 33-language and 13-theme contract passes | 136 ms | 0.19 s / 59.7 MB | Retain baseline |
| HighlighterSwift 3.1.0 (`fe7aae9`) | Swift 6 builds; missing `xcode-dark`; 1,353 missing-style warnings in the focused matrix | 220 ms (+61.8%) | 0.26 s / 59.7 MB | Reject |
| [HighlightSwift 1.1.0](https://github.com/appstefan/HighlightSwift) (`784ca3c`) | Swift 6, actor-isolated API; several required theme families are absent; integration is async-only | Not integrated | 2.20 s / 53.6 MB | Reject |
| [Splash](https://github.com/JohnSundell/Splash) | Pure Swift, but supports Swift syntax only | Not integrated | Not measured | Reject |
| [Neon](https://github.com/slsrepo/Neon) | Lower-level Tree-sitter styling infrastructure; installs from an unreleased branch and requires grammar/theme product work | Not integrated | Not measured | Reject |
| [LZhenHong/HighlightSwift](https://github.com/LZhenHong/HighlightSwift) 0.0.1 | Very early package with insufficient maintenance evidence | Not integrated | Not measured | Reject |

Both HighlighterSwift 3.1.0 and HighlightSwift 1.1.0 compiled and passed their upstream
tests with Swift 6 and warnings treated as errors. That proves toolchain compatibility,
not Vitrine compatibility. HighlighterSwift's product spike still crossed the allowed 10%
performance-regression limit, omitted a shipped Vitrine theme, and emitted runtime style
warnings. Strict golden comparison could not be claimed because the available host was
macOS 26.5.2 while the golden manifest requires 26.5.0; render-only qualification passed.

## Replacement gates

Reconsider the decision only for a stable, maintained release that:

1. recognizes all 33 advertised language identifiers and all 13 built-in themes;
2. supports custom Vitrine palettes without network access or remote assets;
3. compiles in Swift 6 with warnings treated as errors and no unsafe concurrency escape;
4. emits no missing-style or runtime compatibility warnings in the full matrix;
5. preserves App/CLI normalized-pixel parity and passes strict goldens on the pinned host;
6. keeps product highlighting p95 and isolated peak RSS within 110% of the baseline;
7. either fits the synchronous rendering adapter or is adopted with a separately qualified
   async rendering architecture.

## Consequences

- The app preserves its existing visual output, theme catalog, and performance envelope.
- The dependency remains exact-version pinned and isolated behind one module boundary.
- Direct theme-catalog tests now catch renamed or removed bundled styles before release.
- Highlightr's inactive maintenance status remains a supply-chain and modernization risk;
  the gates above make a future migration evidence-driven and reviewable.
