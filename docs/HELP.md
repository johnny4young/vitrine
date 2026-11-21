# Vitrine Help

This is the source of truth for Vitrine's in-app Help content. The Help window
(`Vitrine/Help/HelpView.swift`) renders these topics from bundled copy, so help is
available **offline** with no web dependency. Keep this document and the in-app
copy in step: when you change one, change the other.

Open Help from the **Help ▸ Vitrine Help** menu (or press `⌘?`). Each topic has a
button that opens what it describes; none of them runs a capture.

## The global hotkey

The global hotkey is optional. New installations start without one; existing
choices and explicit deactivations are preserved. Set, change, or clear it from
the Help window or **Settings ▸ General**. It works across apps when enabled.
The menu-bar action remains available without a shortcut.

## Quick capture

Copy code anywhere, choose **New Capture from Clipboard** from Vitrine's
menu-bar panel, press `⇧⌘S` in Vitrine, or use your enabled hotkey, and Vitrine
renders it with your current style. With **Copy to clipboard automatically** on (the default), a
successful copy places the image on your clipboard; paste it into a document,
chat, or pull request. If copying fails, Vitrine reports the
failure instead of claiming success.

## The editor

Open the editor (**File ▸ Open Editor**, or `⌘E`) to paste or type code, pick a
language and theme, and fine-tune padding, corner radius, window chrome, and line
numbers. Copy, save, or share the result from the toolbar or the **File** menu.

## Presets

- **Destination presets** size the image for where it is going — a README, a social
  card, or a slide.
- **Style presets** save a look you like so you can reapply it in one click.

Choose destination presets in **Settings ▸ Style** or **Settings ▸ Export**. Manage
saved style presets and custom themes in **Settings ▸ Library**.

Deleting a saved preset or custom theme asks for confirmation and names the item.
**Cancel** (also Return or Escape) leaves it unchanged. Preset deletion does not alter
your current style. Deleting your active default custom theme replaces only that theme
with One Dark, as the confirmation explains; other style settings and open editor
snapshots stay unchanged. Built-in presets and themes cannot be deleted.

## Privacy

Code rendering is local and requires no Vitrine account, Screen Recording, or
Accessibility-control permission. The direct-download build can use the network
for an explicitly requested webpage or remote image, updates, and license
activation; the App Store build has no network-client entitlement. A requested
webpage loads on this Mac, but the website still receives a request. See the
[capability reference](CAPABILITIES.md) and [permissions](PERMISSIONS.md) for
retention, consent, and channel details. Review web capture's network use in **Settings ▸ Input**.

**Embed editable project in PNG files** (**Settings ▸ Output**, off by default) puts the
source code, style, header, annotations and alt text inside saved PNGs. Anyone with the file
can extract that source code. Only the editor's Save Image and quick capture's **Also save to
a file** embed it; clipboard copies, multi-size and carousel exports, comparison boards,
Recents, Services, App Intents and the CLI never do. Redacted lines, blur boxes, terminal
captures and anything the secret check flags keep the project out of the file. Dropping such
a PNG on the editor asks whether to open it as a project or use it as an image.

## What's New

Vitrine shows version-aware release notes once per new version (**Help ▸ What's
New**). The notes are bundled in the app (`Vitrine/Help/ReleaseNotes.swift`), so
this surface is also fully offline. What's New never appears on a clean first run —
the first-run quick-start owns that — and is skippable. See
[`docs/RELEASING.md`](RELEASING.md) for how release notes are authored as part of
the release checklist.

### Version 2.0.0

The current source bundle's newest note is **Made for code review and storytelling**:

- diffs show side by side, mark the words that changed, fold hunks out of the image, and carry
  comments pinned to lines (⇧⌘M);
- a box can become a magnifier, arrows switch between straight, curved and elbow, and marks
  can take a hand-drawn stroke from the toolbar beside them;
- code steps store versions of the code and animate the preview between them;
- carousels preview their real slides, come in four sizes, and take captions plus cover and
  closing slides;
- comparison boards gain a Slider layout, theme variants, and scenes exported as PNGs or a PDF;
- Export Sizes renders every selected platform size at once, with a focal point;
- canvas mode (⇧⌘F) hides the code and inspector columns, and clicking a part of the preview
  opens the controls that style it;
- likely secrets are checked before copying, saving, sharing, or exporting; and
- the supported floor is macOS 26 Tahoe on Apple silicon; version 1.3.0 remains the release for
  macOS 15 Sequoia and Intel Macs.

The Releases page remains the authority for what is publicly downloadable; preparing these
bundled notes in source does not publish or deploy version 2.0.0.
