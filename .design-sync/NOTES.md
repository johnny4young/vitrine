# design-sync notes — Vitrine

## This repo is outside the converter's envelope

Vitrine is a **SwiftUI macOS app**, not a JS component package. There is no
bundlable `dist/`, so `package-build.mjs` / the esbuild converter does **not**
apply and must never be run against this project — it would replace a curated,
hand-authored design system with a generated layout.

The remote project's components are **React mirrors** of the SwiftUI design
system, authored by hand against the CSS custom properties in `tokens/`. A push
is therefore a set of targeted writes in the project's own conventions.

## Project conventions (match these when adding components)

- Plain React function components, `import React from "react"`, inline styles,
  every value via `var(--token)`. No CSS files per component.
- One trio per component: `<Name>.jsx` + `<Name>.d.ts` (`<Name>Props`) +
  `<Name>.prompt.md`.
- One `*.card.html` per group, first line `<!-- @dsCard group="…" viewport="WxH"
  name="…" subtitle="…" -->`, pinned React/ReactDOM/Babel CDN scripts **with
  integrity hashes** (copy them from an existing card), and
  `<script src="../../_ds_bundle.js">`.
- Cards consume `window.VitrineDesignSystem_2a4531`.

## `_ds_bundle.js` and `_ds_manifest.json` are COMPILED BY THE APP

Both are build outputs (`"source":"spa"` in the manifest; each component entry
carries a `sourcePath`). Do not hand-write them.

Write `_ds_needs_recompile` (any content) as the **last** write of a push. The
app rebuilds the bundle and the manifest the next time the project is opened.

**Verified 2026-08-27:** immediately after a push the manifest is still the old
one — the recompile is not synchronous and does not happen server-side on write.
So new components are not in `window.VitrineDesignSystem_2a4531`, and any new
card that imports them renders blank, **until someone opens the project**. That
is expected; don't chase it as a bug, and don't try to regenerate the bundle
locally to "fix" it.

## Screenshots: use CI, not a local UI-test run

`uploads/ui-audit/` should hold the 53-state strict visual tour. Do **not** run
`make test-visual` locally just to refresh it — it drives XCUITest with synthetic
input that can hit whatever app is frontmost. Download the vetted artifact from
any green CI run on `main` instead:

```
gh run list --branch main --workflow ci.yml --limit 5 \
  --json databaseId,conclusion,headSha
gh api repos/johnny4young/vitrine/actions/runs/<id>/artifacts \
  --jq '.artifacts[].name'
gh run download <id> -R johnny4young/vitrine -n screenshot-tour-tahoe-26
```

Artifacts keep ~90 days. Two sets are produced per run: `…-tahoe-26` and
`…-sequoia-15`. Tahoe is what we upload (newest macOS = where design should aim).

Slugs change between releases. Diff the new set against the remote listing and
**delete** the stale slugs, or the project keeps showing UI that no longer exists
(e.g. `11-editor-inspector-background` → `11-editor-inspector-output`).

## The landing folder

`landing/index.html` is the **2026-06 design proposal** (historical — it was
adopted into what became the site). The **live** site is Astro under `site/` in
this repo and is pushed to `landing/site/`.

`npm run build` emits **root-absolute** asset paths (`/static/…`, `/screenshots/…`),
which do not resolve from `landing/site/`. Rewrite them to relative before
uploading — anchor the substitution on `="/` so absolute `https://` URLs
(canonical, og:url) are left alone. Drop `_headers`, `robots.txt` and the
sitemaps; they are server/crawler files, not design artifacts.

## Verifying components before a push

There is no Storybook. The recipe below bundles the staged `.jsx` into the
staging mirror and serves that mirror over HTTP, so the cards resolve
`../../_ds_bundle.js` and `../../styles.css` exactly as they will in the
project. `file://` will not do: the cards use relative paths.

**Run every command from `docs/design/`.** The working directory is the whole
trick here, and getting it wrong fails in two different ways: from the repo
root, `--outfile=_ds_bundle.js` drops the bundle at the root where no card
looks for it; from `docs/design/`, `site/node_modules/...` does not exist, which
is why esbuild is invoked through `../../`.

```bash
cd docs/design                 # the staging mirror IS the web root

mkdir -p _verify
printf 'export default window.React;\n' > _verify/react-shim.js
find components -name '*.jsx' | sort \
  | sed 's|^|export * from "../|; s|$|";|' > _verify/entry.js

../../site/node_modules/.bin/esbuild _verify/entry.js --bundle --format=iife \
  --global-name=VitrineDesignSystem_2a4531 --alias:react=./_verify/react-shim.js \
  --jsx=transform --outfile=_ds_bundle.js

python3 -m http.server 8765    # open /components/<group>/<name>.card.html
```

A card that also uses a component which exists only in the **remote** bundle
(`Switch`, `InspectorRow`, `PopUpButton`, `Slider`, `CodeCard`, `TrafficLights`)
will not find it locally — add a throwaway `_verify/legacy-stubs.jsx` exporting
a minimal version of each and re-export it from `entry.js`.

Reconstruct `styles.css` locally from the token list inside `_ds_manifest.json`
(it carries every name, value and scope).

**Delete every local stub before uploading** — `_verify/`, `styles.css`,
`_ds_bundle.js` and `ui_kits/appearance-toggle.js`. The last three would
overwrite the real remote files, and `styles.css` in particular is the entry
point every rendered design depends on.

`esbuild --loader=jsx` only applies to stdin; for files the extension decides.
