<!--
Thanks for contributing to Vitrine! A small, focused PR is the fastest to review.
Conventions live in CONTRIBUTING.md and AGENTS.md.
-->

## What does this change?

<!-- One or two sentences: what and why. Link the issue if there is one. -->

Fixes #

## Checklist

- [ ] `make format` ran and `make lint` passes.
- [ ] `make test` passes locally (1,000+ unit tests, ~25 s).
- [ ] UI-visible change? `make build-ui-tests` compiles, and the relevant
      `UITests/` smoke still matches the new UI.
- [ ] Edited `project.yml` (never the generated `.xcodeproj`) if the project
      structure changed, and ran `make project`.
- [ ] New user-facing strings are in the String Catalog with an `es` translation
      (the `LocalizationTests` gate enforces this).
- [ ] Visual change to the **exported image**? Regenerated goldens
      (`make record-goldens`) and the gallery (`make gallery`) deliberately.
- [ ] Visual change to the **app chrome**? Values come from the token layer
      (`Vitrine/DesignSystem/`), not hard-coded hexes; both light and dark
      appearances checked.
- [ ] Commit subjects are conventional and imperative; **no AI co-authorship /
      "generated-by" trailers**.

## Screenshots

<!-- For UI changes: before/after, light and dark. -->
