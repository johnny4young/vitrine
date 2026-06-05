# Design QA & the launch gallery (CS-039)

> A screenshot app should ship with **evidence** of its visual quality, not rely on
> subjective memory. Vitrine's design QA is a generated **launch gallery**: a set of
> representative code screenshots rendered through the real export pipeline, committed
> to the repo, and reviewed against on every release.

The gallery is **generated from the app renderer**, never hand-made mockups, so what
you review is exactly what a user gets. The same images feed the README and release
notes.

## What's in the gallery

The catalog lives in one place — [`Tests/SampleGallery.swift`](../Tests/SampleGallery.swift)
(`SampleGallery.all`) — and the committed PNGs plus a manifest live under
[`Tests/Fixtures/Samples/`](../Tests/Fixtures/Samples). Every sample is fully
deterministic: each pixel-affecting field of its `SnapshotConfig` and the render scale
are pinned.

The set provably covers the surfaces a code-image tool is judged on (each category is
asserted to be represented):

| Category | What it shows | Examples |
| --- | --- | --- |
| **Languages** | Real highlighting per language, each on a complementary theme | Python, TypeScript, Go, Rust, SQL |
| **Themes** | Every built-in theme over one snippet, isolating the syntax palette | One Dark, Dracula, Nord, Tokyo Night, GitHub, One Light, … |
| **Social & export presets** | The framed output for each share surface (CS-020) | X/Twitter, LinkedIn, Keynote, Docs, Transparent Slide, OpenGraph 1200×630 |
| **Transparent backgrounds** | Real alpha (CS-024) with a dark *and* a light code card | `transparent-dark`, `transparent-light` |
| **Accessibility / high contrast** | A **WCAG-AA-verified** high-contrast palette | `a11y-high-contrast` |

### Accessibility / high contrast

The rendered code image takes its contrast from the chosen **theme** — there is no
separate high-contrast *render mode* in the snapshot model — so the accessibility
sample uses a curated high-contrast custom palette
(`SampleGallery.highContrastPalette`). Because that palette's colors are
value-typed, the suite asserts the text-on-card contrast **statically**: the
foreground and every syntax-token color must clear the WCAG AA normal-text threshold
(4.5:1) against the card background, using the same `Brand.Contrast` utilities as the
brand-palette checks (CS-036). A built-in theme can't be checked this way because its
syntax colors only exist inside Highlightr at render time.

> The app *chrome* already adapts to the system **Increase Contrast** setting via the
> brand color set (see [DESIGN-SYSTEM.md](DESIGN-SYSTEM.md)); that is verified
> separately by the CS-036 contrast tests. This gallery covers the **exported image**.

## Regenerating the gallery

One command renders every sample through the export pipeline and refreshes the
committed PNGs + manifest:

```bash
make gallery
```

Under the hood (the same staging dance as the golden fixtures, CS-025): the unit-test
host is sandboxed and can't write into the source tree, so the opt-in generator suite
(`SampleGalleryGeneratorTests`, armed by `VITRINE_GENERATE_GALLERY=1`) stages the
files in its container temp and prints a `GALLERY OUTPUT <path>` line.
[`scripts/generate-launch-gallery.swift`](../scripts/generate-launch-gallery.swift)
drives that suite and copies the staged files into `Tests/Fixtures/Samples/`. Review
the diff and commit it when a deliberate visual change lands.

### Adding a sample

Adding a sample is a **one-file change**: append a `Sample` to the right category
builder in `Tests/SampleGallery.swift`. It then flows automatically into the render
regression, the generator, the manifest, and the artifact-presence checks — no other
file to touch. Run `make gallery` to produce its PNG.

## How it's enforced

Three suites read the one catalog, so a sample can never drift between them (mirroring
the golden-image architecture, CS-025):

1. **Render regression — always on.** `SampleGalleryTests` renders every sample on any
   machine and fails if the pipeline stops producing an image, asserts each category
   is represented and ids are unique, checks the OpenGraph sample is exactly 1200×630,
   and asserts the accessibility palette meets WCAG AA. A routine `make test`
   exercises the full set end to end.
2. **Artifact presence — always on once committed.** `SampleArtifactTests` asserts the
   committed PNGs and `manifest.json` exist and stay in sync with the catalog (counts,
   ids, per-sample config fingerprints, categories). A dropped or stale sample fails
   CI. Before the first `make gallery`, these checks are informational so the catalog
   can land before the fixtures are recorded.
3. **Generator — opt-in.** Isolated from the checks above so the suite can never
   silently "fix" a missing artifact; regenerating is always an explicit, reviewed
   `make gallery` step.

### CI

CI runs the unit suite (which includes the gallery render regression and artifact
checks). On **failure**, the workflow uploads the freshly rendered gallery so a
reviewer can eyeball the actual images instead of guessing from a log — the gallery
samples are regenerated into a temp directory and attached as a build artifact. This
makes a visual regression reviewable from the PR.

## Release checklist

The launch gallery is part of the release gate. Before tagging a release
(see [RELEASING.md](RELEASING.md)):

- [ ] `make test` green (includes the gallery render regression + artifact checks).
- [ ] If a visual change landed, `make gallery` re-run and the committed
      `Tests/Fixtures/Samples/` diff reviewed.
- [ ] **Visual review against the launch gallery** — open the committed PNGs and
      confirm every category (languages, themes, presets, transparent, accessibility)
      still looks correct; no regressions in chrome, padding, syntax colors, or alpha.
