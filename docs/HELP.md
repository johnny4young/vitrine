# Vitrine Help

This is the source of truth for Vitrine's in-app Help content. The Help window
(`Vitrine/Help/HelpView.swift`) renders these topics from bundled copy, so help is
available **offline** with no web dependency. Keep this document and the in-app
copy in step: when you change one, change the other.

Open Help from the **Help ▸ Vitrine Help** menu (or press `⌘?`).

## The global hotkey

Press the global hotkey from any app to capture whatever code is on your clipboard
as an image. The default is `⌘⇧S`. Set or change it from the Help window, or in
**Settings ▸ General**.

## Quick capture

Copy code anywhere, press the hotkey, and Vitrine renders it with your current
style. The image is placed on your clipboard automatically — paste it straight into
a document, chat, or pull request. You can also start a capture from the menu-bar
icon.

## The editor

Open the editor (**File ▸ Open Editor**, or `⌘E`) to paste or type code, pick a
language and theme, and fine-tune padding, corner radius, window chrome, and line
numbers. Copy, save, or share the result from the toolbar or the **File** menu.

## Presets

- **Destination presets** size the image for where it is going — a README, a social
  card, or a slide.
- **Style presets** save a look you like so you can reapply it in one click.

Manage both in **Settings ▸ Style**.

## Privacy

Vitrine is private by design: your code never leaves your Mac. There is no account
and no network access, and rendering needs no screen-recording or Accessibility
permission. See [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) for the full posture.

## What's New

Vitrine shows version-aware release notes once per new version (**Help ▸ What's
New**). The notes are bundled in the app (`Vitrine/Help/ReleaseNotes.swift`), so
this surface is also fully offline. What's New never appears on a clean first run —
the first-run quick-start owns that — and is skippable. See
[`docs/RELEASING.md`](RELEASING.md) for how release notes are authored as part of
the release checklist.

### Version 1.2.1

The current source bundle's newest note is **Safer rendering, stricter web capture**:

- extreme canvas and full-page Web Snapshot sizes are rejected before unsafe bitmap
  allocation, with actionable errors instead of blank output;
- app, CLI, Shortcuts, batch, social-card, and comparison-board exports preserve the same
  typed render failures;
- Web Snapshot blocks literal local and private subresources across images, styles,
  scripts, frames, and network requests unless loopback is explicitly enabled;
- CodeQL and focused Address and Thread Sanitizer lanes add repeatable candidate evidence;
  and
- the supported floor remains macOS 15 Sequoia, with Tahoe qualification and universal
  direct downloads.

The Releases page remains the authority for what is publicly downloadable; preparing these
bundled notes in source does not publish or deploy version 1.2.1.
