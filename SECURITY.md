# Security Policy

## Supported versions

Only the latest release of Vitrine receives security fixes. Auto-updates ship
through the Sparkle channel (DMG installs) and the Homebrew cask, so staying
current is one click.

| Version | Supported |
| ------- | --------- |
| latest release | ✅ |
| anything older | ❌ |

## Reporting a vulnerability

Please **do not open a public issue** for security problems. Instead, report
privately through
[GitHub Security Advisories](https://github.com/johnny4young/vitrine/security/advisories/new),
which only the maintainer can read.

Include what you can: affected version, macOS version, reproduction steps, and
impact. You can expect an acknowledgment within a few days; fixes ship as a
regular tagged release with credit in the release notes (unless you prefer to
stay anonymous).

## Scope notes

Vitrine is deliberately small in attack surface:

- The app is **sandboxed** and ships **without the network entitlement** — code
  rendering is fully local, with no account, no server, and no telemetry.
- Pasted-HTML rendering is local and blocks remote resource loads.
- The update channel is EdDSA-signed (Sparkle); the release pipeline notarizes
  every DMG and publishes a SHA-256 alongside it.

Findings about the release pipeline (appcast, signing, cask) are absolutely in
scope — treat the supply chain as part of the app. The entitlement-by-entitlement
audit lives in [docs/PERMISSIONS.md](docs/PERMISSIONS.md).
