# Vitrine site (`site/`)

The public website for [vitrineframe.app](https://vitrineframe.app) lives here as a
standalone Astro package. Astro renders static HTML; all browser behavior uses small,
framework-free JavaScript modules. There is no React runtime or client-side application
shell.

The component boundaries preserve the established vitrineframe.app gallery design: the
salon hero, interactive style bench, product stories, responsive board, changelog, PRO
offer, and installation flow remain separate visual regions rather than a redesign.

## Local development

Requires Node.js 22.12 or newer.

Package versions are pinned exactly for reproducible deploys. TypeScript stays on the
newest stable release accepted by `@astrojs/check` rather than forcing an incompatible
major version through its peer-dependency contract.

The `sharp` override keeps Wrangler's transitive image tooling on the same `sharp` build as
the site's own image scripts. Miniflare pins an exact `sharp` release that can trail the
`devDependencies` entry, so without the override npm installs a second, older copy with an
older libvips build. Keep the override equal to the `devDependencies` version, and remove it
once Miniflare's own pin reaches that version.

The `http-cache-semantics` (4.3.0, GHSA-ch52-4w7c-c8xp), `source-map-js` (1.2.2,
GHSA-68fv-2mgg-jv7q), and `nanoid` (3.3.18) overrides hold transitive build dependencies on
patched releases inside the ranges their dependents declare. The `undici` override equals
Miniflare's exact 7.29.1 pin, but it also moves Astro's `unifont`, which declares `^8.0.0`,
onto 7.x; that path is unused because the site configures no Astro fonts. Overrides are exact
pins, so a later advisory needs an override bump, not only a lockfile refresh. Remove each one
once every dependent's own range excludes the vulnerable releases.

```bash
cd site
npm ci
npm run dev
```

## Validation

```bash
npm test
```

The build validator checks both language routes, canonical and alternate-language
metadata, structured data, core gallery sections, browser-script syntax, crawl files,
internal links, and the social-card dimensions. Both home pages render all 100 marketing
messages from `src/i18n/content.ts` at build time; navigation, accessible labels and image
descriptions share the typed locale catalog. Rich-text messages are trusted repository
content only, never user input or release API data.

Language switches are native links on both the home and CLI pages, including when
JavaScript is disabled. Browser scripts handle only optional interactions and release
lookup; `/download` retains its manual release link without JavaScript. The postbuild
tests reject English fallback in Spanish sections, omitted or duplicated messages, and
JavaScript-only or incorrectly routed language controls. Product names and source-code
samples are intentionally not translated.
Static release highlights and structured data track `project.yml`; they do not authorize a
download. The optional release lookup accepts only a published stable GitHub release and
its uploaded, nonempty, matching Vitrine DMG from this repository. Missing assets fall back
to that release page; offline, invalid, or rate-limited responses preserve `/download` and
its manual link. Both routes share `public/scripts/release.js` and its adversarial tests.

## Images and caching

`npm run images` generates content-addressed WebP variants from the original PNGs in
`public/`; development, checking, and build scripts run it automatically, reusing outputs
for unchanged sources. Original paths
remain available for README links and PNG fallback. Generated files are ignored, not
hand-edited. `ResponsiveImage.astro` emits native `picture`, responsive source widths,
explicit geometry and localized alt text without a client framework.

WebP compression is lossless at each selected resolution. Postbuild tests compare decoded
visible pixels against the resized original, check every emitted file and content hash,
and enforce a byte reduction. Smaller candidates that cost more bytes than a larger one
are omitted. Screenshots retain their native-resolution candidate; browser-selected sizes
still need visual review at desktop/mobile widths and Retina density. The CLI hero loads
eagerly; below-the-fold screenshots remain lazy.

`_headers` applies immutable caching only to generated `/static/*` and `/responsive/*`
assets. Original screenshot URLs retain a bounded cache and mutable scripts/HTML are not
marked immutable. Tests validate the built rules and actual asset paths, **not deployed
response headers**. Confirm those separately after an approved deployment.

The lockfile updates transitive `devalue` to 5.9.4 for
[GHSA-9rgm-9g3h-6x36](https://github.com/sveltejs/devalue/security/advisories/GHSA-9rgm-9g3h-6x36).
This static site has no Astro Actions/server runtime accepting untrusted devalue payloads;
the dependency is patched regardless. No public vulnerability exception is required.

## Deployment

`.github/workflows/deploy-site.yml` builds this package and deploys `dist/` to the
`vitrine-web` Cloudflare Pages project. A push to `main` that changes `site/` only
validates the build; production changes only when the release workflow calls it with the
promoted tag, or through a manual dispatch whose `release_ref` names a published stable
tag.

### Visual accessibility checks

The preview filename follows the selected snippet foreground, independently of the
page appearance. Script regression tests exercise each theme and language and check
normal-text contrast; this DOM double does not prove browser layout. A stylesheet contract
test requires every hover or press transform to be neutralized under Reduce Motion and
keeps CLI examples shrinkable in narrow grids.

Before integrating visual changes, inspect EN/ES home and CLI in a real browser at
390 px and 1280×800, with JavaScript enabled and disabled. Check that CLI examples
stay within the page while long code remains locally scrollable, preview filenames
remain readable in every theme/page-appearance combination, and keyboard focus is
visible. With Reduce Motion enabled, anchor navigation must not smooth-scroll and
hover and press states must not move controls. Keep screenshots and measured computed styles with
the exact commit under review; automated source checks are not a screen-reader audit.
