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

Choose destination presets in **Settings ▸ Style**. Manage saved style presets and
custom themes in **Settings ▸ Library**.

Deleting a saved preset or custom theme asks for confirmation and names the item.
**Cancel** (also Return or Escape) leaves it unchanged. Preset deletion does not alter
your current style. Deleting your active default custom theme replaces only that theme
with One Dark, as the confirmation explains; other style settings and open editor
snapshots stay unchanged. Built-in presets and themes cannot be deleted.

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

### Version 1.2.3

The current source bundle's newest note is **An editor that keeps up**:

- a keystroke no longer re-measures the whole editor window or re-evaluates the inspector;
  only the views that show the document text update;
- a padding or font-size step updates the editor once instead of twice, and the code editor
  reapplies its font only when the font actually changes;
- highlighting results cover every font-size step and built-in theme, so revisiting one
  reuses the earlier result;
- launch removes stale per-window settings from earlier versions in the background;
- the signed app no longer contains the development and release-QA launch hooks; and
- the supported floor remains macOS 15 Sequoia, with Tahoe qualification and universal
  direct downloads.

The Releases page remains the authority for what is publicly downloadable; preparing these
bundled notes in source does not publish or deploy version 1.2.3.
