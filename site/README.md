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
internal links, and the social-card dimensions.
The displayed release version and structured data come from the repository's authoritative
`project.yml`, so a release version bump cannot leave static website metadata behind.

## Deployment

`.github/workflows/deploy-site.yml` builds this package and deploys `dist/` to the
`vitrine-web` Cloudflare Pages project. Deployments run when `site/` changes, when a
GitHub release is published, or through a manual workflow dispatch.
