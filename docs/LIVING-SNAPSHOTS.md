# Living snapshots

Living snapshots keep one explicitly selected source file connected to one Vitrine
editor window. They shorten a repeated **edit → save → recapture** loop without turning
Vitrine into a project indexer or background file service.

## Use the workflow

1. Open an editor and choose **Live file** in the code-pane header.
2. Select one text or source file, then confirm **Replace & Watch** if the editor already
   contains code.
3. Save that file in your usual editor.
4. Vitrine refreshes the code and preview when its editor still contains the last loaded
   version.

The live-file menu also provides **Reload from File**, **Open Different Live File**, and
**Stop Watching**.

## Local edits are protected

Vitrine remembers the exact text last loaded from disk. If the code pane has changed
since then, a newer saved file is not applied automatically. The editor shows two
choices:

- **Reload** discards the local editor draft and loads the newest readable file version.
- **Keep** dismisses that saved version while leaving the watcher active for a
  future save.

Content-bound highlights, redactions, and annotations are cleared only when changed
file content is actually loaded. A save whose text is unchanged leaves those marks
alone.

## Privacy and lifetime

- File selection is explicit. Vitrine does not search a repository, parent folder, or
  workspace.
- The source is read-only from Vitrine's perspective; the app never writes back to it.
- Security-scoped access exists only while the watcher is active in the current editor
  window.
- No source URL or bookmark is stored in app settings or window restoration.
- Closing the editor, stopping the watcher, loading a replacement document, or switching
  to image content releases access immediately.
- The loaded text behaves like any other editor draft and may participate in normal
  draft restoration, but the live connection itself is never restored.
- No network permission, Screen Recording permission, Accessibility permission, or new
  entitlement is required.

Ordinary drag and drop remains a one-time import. Use **Live file** only when you want an
ongoing connection for the current window.

## Save behavior

Many editors save safely by writing a temporary file and replacing the original. Vitrine
therefore observes a lightweight path fingerprint rather than attaching permanently to
one file inode. It checks file size, modification date, resource identity, and the
filesystem file/volume numbers, then reads content only after that fingerprint changes.
A temporary read failure leaves the change retryable on the next check.

If the path stays unavailable, the code pane reports **Live file unavailable**. Restore
the file and choose **Retry**, open a different source, or stop watching.
