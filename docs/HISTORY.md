# Local capture history

History is local to this Mac. It records quick captures (including explicit URL-as-text
recovery), not every edit, handoff, or export. Its retention decision is separate from the
output requested by the user: a history warning does not silently change that export.

## New captures

- Settings → Export → History can disable new history writes. Existing captures and
  previews remain until explicitly deleted. Pinning existing captures remains available.
- Explicitly redacted rows are removed before a record or thumbnail can be created. The
  retained terminal representation uses the same resolved rows as private exports; it
  never falls back to a pre-redaction ANSI transcript. Blur annotations are visual effects,
  not source-text redaction.
- A heuristic secret match stops automatic retention. For that capture only, choose
  **Don't Save**, **Save Sanitized**, or **Keep Original**. Dismissing is no-save; consent is
  never remembered. No pending original is written to disk. **Keep Original** retains
  flagged text deliberately, but cannot restore explicitly redacted rows.
- Sanitized history removes detected visible rows. Terminal captures are flattened to
  their final visible screen, removing overwritten transcript content as well. Detection
  is heuristic, not proof that every secret has been removed.
- Text hidden behind a foreground image is not added to text history.

The history list, search, reopening, and thumbnails all consume the same approved text.
Disabling or clearing history while a decision is open invalidates that older decision.

## Older or damaged history

Older history receives a notice with an explicit keep/delete choice. Keeping it does not
retroactively sanitize it. Deleting all history removes pinned and unpinned records plus
Vitrine's cached previews; it does not erase OS backups, exported files, or other apps' copies.

If an archive has invalid records or a truncated JSON array, Vitrine recovers complete valid
entries in memory and retains the original stored bytes and cached previews. It does not
silently replace the archive with an empty list, prune its cache, or append new captures.
Choose **Recover Valid Captures** to replace the damaged archive with those readable entries;
unreadable entries are discarded only after confirmation. With no readable entries, the
original remains until explicit deletion. Recovery cannot reconstruct missing bytes.
