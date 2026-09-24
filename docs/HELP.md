# Vitrine Help

This is the source of truth for Vitrine's in-app Help content. The Help window
(`Vitrine/Help/HelpView.swift`) renders these topics from bundled copy, so help is
available **offline** with no web dependency. Keep this document and the in-app
copy in step: when you change one, change the other.

Open Help from the **Help ▸ Vitrine Help** menu (or press `⌘?`).

## The global hotkey

The global hotkey is optional. New installations start without one; existing
choices and explicit deactivations are preserved. Set, change, or clear it from
the Help window or **Settings ▸ General**. It works across apps when enabled.
The menu-bar action remains available without a shortcut.

## Quick capture

Copy code anywhere, choose **New Capture from Clipboard** from Vitrine's
menu-bar panel (or use your enabled hotkey), and Vitrine renders it with your
current style. A successful copy places the image on your clipboard; paste it
into a document, chat, or pull request. If copying fails, Vitrine reports the
failure instead of claiming success.

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

Code rendering is local and requires no Vitrine account, Screen Recording, or
Accessibility-control permission. The direct-download build can use the network
for an explicitly requested webpage or remote image, updates, and license
activation; the App Store build has no network-client entitlement. A requested
webpage loads on this Mac, but the website still receives a request. See the
[capability reference](CAPABILITIES.md) and [permissions](PERMISSIONS.md) for
retention, consent, and channel details.

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
