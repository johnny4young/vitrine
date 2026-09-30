# Create your first code image

This tutorial creates one image from a **synthetic** Swift snippet. It works in the
free app on either distribution channel, needs no account or network connection,
and uses no real project code, path, or credential. By the end, you will have an
image on your clipboard that you can paste into another app.

## Before you begin

Install Vitrine from the [latest published release](https://github.com/johnny4young/vitrine/releases/latest)
or the Homebrew cask. The version in source control may be newer than the latest
published download. The app runs on macOS 15 or later.

This is the entire sample; it is also checked in as
[`docs/examples/first-capture.swift`](examples/first-capture.swift):

```swift
struct ReleaseNote {
    let title = "A clear first image"
    let checks = ["render", "review", "share"]

    var summary: String {
        "\(title): \(checks.count) checks"
    }
}
```

## Make the image

1. Copy the sample above. Open Vitrine from its menu-bar icon and choose **Open
   Editor**. You should see an editor window, not a Dock app that needs a separate
   sign-in.
2. The editor opens your current document, so select any existing code (⌘A)
   before you paste. Paste the snippet into the code editor. The preview should
   show highlighted Swift code. If another language is selected, choose **Swift**
   in the language picker. Nothing is uploaded to render this preview.
3. Pick a theme and background you like. Leave the default output size for this
   first run. The preview should change immediately while the source text stays
   the same.
4. Choose **Copy image** in the editor. Wait for Vitrine's success feedback; a failed
   copy should report failure rather than claiming success. Paste into Notes,
   Keynote, or another app that accepts images. You should see a code image,
   not the text of the snippet.

If you prefer a file, use the editor's **Save Image** action (⌘S) instead and
choose a destination.
No PRO purchase is needed for this single image. The
[capability reference](CAPABILITIES.md) shows which later actions are PRO or
channel-specific.

## Optional next steps

- Copy the sample again (Copy image replaced it on the clipboard), then try the
  menu-bar quick capture. A global shortcut is optional and can be enabled or
  reassigned in Settings; it is not required for this tutorial.
- Before sharing real content, inspect the preview and use **Redact secrets**
  when needed. Heuristic detection is not a guarantee; see the
  [privacy contract](CAPABILITIES.md#privacy-and-retention).
- On the direct-download/Homebrew channel, save the sample as
  `first-capture.swift`; the free CLI handoff `vitrine render first-capture.swift --edit`
  opens it in the editor. Homebrew puts `vitrine` on `PATH`; for a DMG install, use
  **Settings ▸ General ▸ Command-line tool** first. Rendering to a file with
  `--out` is a separate PRO operation.
  The Mac App Store build does not ship the CLI.

The shortcut recorder keeps the library's conflict validation: combinations already
used by Vitrine's app menus, including ⇧⌘S, cannot be assigned there. Choose an
available combination instead. Existing assignments and disabled shortcuts are
preserved; Vitrine never remaps or re-enables them automatically.

For a visual orientation, see the
[first-run quick-start screenshot](../site/public/screenshots/welcome.png).
The screenshot is illustrative; the steps above use the checked-in sample rather
than a real capture.

The quick-start image is an unmodified native screenshot from the
[qualified macOS UI tour](https://github.com/johnny4young/vitrine/actions/runs/36627727922)
on commit `e166d57d759e887c768ca6742e0f599803c7d00d`, with a fresh isolated
installation and no assigned global shortcut.
