# Documentation export

This capability belongs to current source, not the v1.2.3 download. One-document
GUI packages and manual alternative text are Free in Direct and Store builds.
General CLI rendering, sidecars, multi-size, and batch retain their existing PRO policy.

## In the editor

Expand **Output** in the inspector and write optional **Alternative text**. It describes
this image in Markdown and HTML; it does not draw another header or change the pixels.
The limit is 1,024 Unicode characters. Blank input restores the existing fallback;
excess input is rejected with feedback, not silently truncated. This is explicitly
written content, not a generated description or an automatic secret filter.

Choose **Export for Documentation** from the copy-options menu, compact actions menu,
or command palette. Markdown is selected initially; HTML and plain text are optional.
Choose a parent directory and a new folder name. The resulting package contains:

- `image.png`: one render with the editor's scale, size, and raster color profile.
- `README.md`: a relative image link and fenced, copyable source when available.
- `index.html`: static, escaped markup with the same relative image and source.
- `source.txt`: safe plain text, only for code or terminal captures.

Imported images have no original source transcript: no empty code fence, residual
editor text, fabricated OCR, or text file accompanies them. The separate **Save Image**
action keeps its PNG/PDF/HEIC/AVIF choices unchanged.

A cancelled folder chooser writes nothing. A failed or cancelled write removes its
own staging directory and never publishes a partial package. The final rename refuses
to replace any existing destination, including an empty directory or symlink. The app
logs neither source content nor chosen filesystem paths.

## Description lifecycle and privacy

Alternative text belongs to this document. Replacing content clears it; restoring a
shared text snapshot restores its own description. Existing links remain readable.
The field is not a style preset, workspace recipe, global preference, or Recents field.
Recents continues to restore its existing source/language/theme contract, not a full
saved editor document. A restored editor draft retains its own description; a new editor does not inherit it.

Copyable source uses the same sanitized representation as other exports, including
final terminal rows and explicit redactions. A visual blur is not a source sanitizer.
Manually authored descriptions may themselves contain sensitive information: review
them before exporting or sharing. Exporting does not write the clipboard or history.

## CLI

```sh
vitrine render example.swift --out image.png --no-overwrite --json \
  --alt-text 'A constant holding the answer.' --sidecars markdown,html,text
```

`--alt-text` uses the same bounded value and markup builders as GUI packages. Without
it, the previous label fallback remains. The flag does not draw on or embed text into
PNG metadata, and `--edit` rejects it: free handoff carries source and language only.
CLI sidecars retain their neighboring filenames and existing per-file write contract;
the new all-or-nothing directory transaction belongs to the explicit GUI action.
