# Comparison boards

Comparison boards combine two to four finished captures into one labelled image for a
before/after explanation, review, release note, or visual decision record.

## Create a board

1. Open **Recents** from the menu-bar panel.
2. Choose **Compare**.
3. Select two to four cards in the order they should appear. The numbered badges show
   that order; select a card again to remove it.
4. Choose **Create Board**.
5. Edit each short label and optional detail, reorder or remove captures, and choose a
   layout:
   - **Auto** keeps two or three captures in one row and uses a two-by-two grid for four.
   - **Row**, **Column**, and **Grid** force a deterministic arrangement.
6. Optionally pick a board size, gap, background, and footer line:
   - **Auto** hugs the cards. **16:10** is 1600 × 1000, **OG** is 1200 × 630, and
     **Square** is 1080 × 1080; cards scale to fit and stay centered. Captions keep a
     readable size, so three or four captures in a **Column** on **OG** draw as a grid.
   - **Transparent** keeps the backdrop's alpha and gives each card a solid fill so its
     white caption stays readable.
   - The footer line is generated from the capture count and cannot be typed.
7. Copy, save, or share the finished board. Save follows the output format and color
   profile selected in **Settings ▸ Export**. The resolution scale is captured when the
   board opens so later Settings changes cannot upscale its already rendered source pixels.
   **OG** always exports at 1× so its pixels are exactly 1200 × 630.

Click a caption on the board to edit it where it will be read. It is the same string as
the inspector row. Return, Escape, a click on the board or its stage, or moving to an
inspector field closes it. Other inspector controls leave it open, so a size or
background can be tried while the caption is being written.

Every card receives the same image area and preserves its aspect ratio. Labels are
single-line and bounded so a board cannot grow unpredictably from pasted text.

## Session and privacy boundary

Comparison mode is explicit and temporary:

- entering it freezes the current gallery search, filter, and sort controls while the
  numbered badges make selection order explicit;
- selection identifiers exist only in that open Recents view;
- creating the board renders each selected capture once;
- the editor draft retains only those finished pixels, visible captions, and the
  layout options above;
- it stores no source path, security-scoped bookmark, source text, or durable Recents
  reference;
- closing the board discards the draft, and nothing is restored on the next launch;
- the footer line names no file, because a board keeps no file name or source text to
  draw it from.

Changing or deleting a Recents entry after the board opens cannot change the board, and
editing a board never mutates capture history or the app's saved style.

## Output contract

Board composition is deterministic for the same pixels, captions, layout, size, gap,
background, footer setting, scale, and color profile. The preview draws through the same
composer as every export, and the caption click targets come from the same metrics. The result uses the shared Vitrine encoders and can be exported as PNG,
HEIC, or PDF according to the current Export setting, plus AVIF when the running macOS
ImageIO stack provides an AVIF writer (Tahoe and newer). PDF contains the finished
board image on one correctly sized page; it does not recreate each source capture as
editable vector content.
