# Terminal / ANSI output → image

Vitrine renders **terminal output** — anything with ANSI color escape codes (`git`,
test runners, `ls --color`, build logs) — as a styled terminal image. The colors come
from the escape codes themselves (standard 16-color, 256-color, and 24-bit truecolor)
with bold / dim / italic / underline / strikethrough / inverse.

It is a first-class **Terminal** language: pasting, dropping a file, quick-capturing,
or `vitrine render … --language terminal` all work, and Vitrine auto-detects terminal
output by its escape codes (they override the file extension, so a `.log`/`.txt` of
colored output is recognized too).

## Quick start

Three ways in, easiest first:

1. **`vgrab <command>`** — about to run something? Prefix it. The command runs with
   color on and a styled image of its output lands on your clipboard; paste anywhere
   (⌘V).
   ```sh
   vgrab npm test
   vgrab git log --oneline --graph -10
   ```
2. **Already ran it?** Recall the command (↑ or `!!`) and prepend `vgrab` — e.g.
   `vgrab !!` re-runs the last command and captures it.
3. **Paste or drop** — paste colored output straight into Vitrine (⌘V), or drop a
   `.log` / `.txt` file; it auto-detects terminal output and styles it.

Add **`-e`** (`vgrab -e <command>`) to open the output in Vitrine's editor — to annotate
or restyle before exporting — instead of copying an image.

`vgrab` needs the one-time shell hook (`eval "$(vitrine shell-init zsh)"`, below).
Paste / drop and the `--stdin` pipe need no setup.

## Use cases

- **Bug reports & GitHub issues** — share a failing `pytest` / `cargo test` with its
  red-and-green intact, not a flat wall of text.
- **PR descriptions & reviews** — a `git diff --stat`, a `git log --graph`, or a green
  test run, dropped inline as an image.
- **Posts & social** — a clean "tests passing" or `git status` that actually looks good
  on X / LinkedIn / Mastodon.
- **Slides, docs & tutorials** — terminal output as a crisp image; pick a light Style
  theme and it renders on a light card to match light slides.
- **Teaching & standups** — show the command and its colored output together, or drop a
  readable build log into Slack.

## Themes

The terminal palette follows the **Style ▸ theme** you pick, so the same theme switch
that restyles a code snapshot restyles a terminal one:

- A **light** theme (GitHub, One Light, …) renders the terminal on a **light** card —
  the right look for light blogs, docs, and slides.
- A **dark** theme renders on a dark card with a balanced One-Dark-family palette.
- **Dracula** and **Nord** map to their own signature ANSI palettes.

## The catch: color is lost when you copy

The hard part isn't Vitrine — it's *getting* colored output. Most programs **disable
color when their output isn't a real terminal** (a pipe, a redirect, a clipboard copy).
So `git status | pbcopy` gives you plain text with the colors already gone, and
selecting text in your terminal copies it without ANSI codes.

The fix is to make the program *think* it's writing to a terminal. The
`vitrine shell-init` helpers do exactly that for you, with zero color flags.

## `vgrab` (recommended)

Install the integration once:

```sh
# ~/.zshrc
eval "$(vitrine shell-init zsh)"
```

Or one-click it: **Vitrine ▸ Settings ▸ General ▸ Shell integration ▸ Set Up…** picks
your startup file and appends that line for you (idempotently). Because the app is
sandboxed, the file picker's grant is what authorizes the write; a "Copy Command"
button gives the equivalent `echo … >> ~/.zshrc` for any setup the panel can't reach.

(Install the CLI itself from Vitrine ▸ Settings ▸ General ▸ Command-line tool ▸
Install…. `vgrab` requires Vitrine PRO, like all CLI rendering.)

Then, in a new shell:

```sh
vgrab git status        # run it and copy a terminal image of its (colored) output
vgrab pytest            # no --color, no unbuffer, no pbcopy
vgrab cargo test
vgrab !!                # capture a command you already ran (re-runs the last one)
```

- **`vgrab <command>`** runs the command inside a pseudo-terminal (via the system
  `script`), so the program emits its colors automatically, captures the output, and
  copies the rendered image to the clipboard. Use it when you're *about to* run
  something. It returns the command's own exit status, so it composes
  (`vgrab make && …`), and **`vgrab -w 100 <command>`** sets the capture width
  (`COLUMNS`) so wide output like `git log --graph` wraps consistently — a best effort,
  since tools that query the terminal size directly ignore it.
- **Already ran something?** Recall it and prepend `vgrab` — `vgrab !!` (zsh/bash)
  expands to your last command and captures it; in any shell, press ↑ and add `vgrab`
  plus a space to the front. This re-runs the command, so it's ideal for read-only output (a
  `git log`, a test run); for slow or side-effecting commands, run them under `vgrab`
  in the first place.
- **`-e` / `--edit`** opens the captured output in Vitrine's **editor** instead of
  copying — to annotate, restyle, or change the theme before exporting.
  `vgrab -e git status` hands the output straight to a Vitrine window (nothing touches
  your clipboard).

### Zero background cost

`vgrab` is just a shell function — it does nothing until you call it. The snippet
**doesn't** re-exec your shell, install a prompt hook, or run anything in the
background, so adding it has no effect on your terminal's performance or behavior.

`vgrab` works in **zsh, bash, and fish** — fish loads it with
`vitrine shell-init fish | source` (fish has no `eval "$(…)"`); the others use the
`eval` line above.

## Full-screen apps (TUIs)

Vitrine doesn't just render scrolling output — it captures **full-screen terminal apps**
too: `htop`, `btop`, `vim`, `lazygit`, `k9s`, `tig`, `less` — anything that paints a fixed
screen by positioning the cursor and redrawing in place.

These apps don't scroll a transcript; they address the screen cell by cell (usually on the
*alternate screen*). Vitrine detects that and switches to a cell-buffer emulator that
replays the cursor moves and reports the **final frame** — the screen you actually saw —
with its colors intact and your chosen theme, font, and background. The surrounding shell
prompt is left out.

```sh
vgrab htop          # captures the dashboard, not an escape-soup transcript
vgrab lazygit
```

The switch is automatic, by content: plain scrolling output (a `git log`, a test run)
keeps rendering the full transcript line by line, unaffected.

## Manual alternatives (no shell integration)

```sh
# Force color yourself, then ⌘V into Vitrine (it auto-detects Terminal):
git -c color.ui=always status | pbcopy
cargo test --color always 2>&1 | pbcopy
CLICOLOR_FORCE=1 ls -la | pbcopy

# Or pipe straight to the renderer:
git -c color.ui=always status | vitrine render --stdin --copy

# Or capture to a file and render / drop it:
cargo test --color always &> test.log
vitrine render test.log --out test.png       # auto-detects ANSI
```

## CLI reference

```
vitrine render <input-file> --out <image> [--language terminal]
vitrine render --stdin --copy                 # read a pipe, copy the image
vitrine render <input-file> --edit            # open it in the editor (no image)
vitrine render <input-file> --out <image> --text-sidecar   # image + .txt of the output
vitrine shell-init [zsh|bash|fish]            # print the helpers
```

`--copy` puts the rendered image on the clipboard; `--stdin` reads the source from a
pipe; `--edit` (`-e`) opens the source in Vitrine's editor instead of rendering — useful
to tweak before exporting; `--text-sidecar` also writes a `.txt` of the output next to
`--out` (terminal escapes stripped). Each detects terminal output by its ANSI escapes
when `--language` is omitted. `--edit` is mutually exclusive with `--copy`/`--out`.

## Notes

- For scrolling output, Vitrine strips the non-color escape sequences (OSC window
  titles, stray controls) and resolves progress-bar carriage returns so the static image
  shows clean, final lines. For a full-screen app it *interprets* the cursor moves
  instead, reconstructing the final frame — see [Full-screen apps (TUIs)](#full-screen-apps-tuis).
- **OSC 8 hyperlinks** (the `ESC]8` links emitted by `gh`, `eza --hyperlink`, some test
  runners) are styled — the linked text is underlined and tinted, the way a link reads —
  while the URL itself stays hidden, exactly as it is in the terminal.
- **Nerd Font / Powerline / icon glyphs.** Private-Use-Area glyphs from `starship`,
  `eza --icons`, and Powerline separators render via a font **cascade** to a Nerd Font
  **you already have installed** (Symbols Nerd Font, a `…Nerd Font` patched family, etc.).
  Vitrine bundles no font — so there is nothing to license and no multi-megabyte asset —
  and falls back gracefully to the previous missing-glyph boxes when no Nerd Font is
  present. (Install any Nerd Font to light these up.)
- **Copyable text alongside the image.** From the command line, `--text-sidecar` writes
  a `.txt` next to the rendered image holding the output as selectable, greppable text —
  the terminal escapes stripped to the visible lines. In the app, **Settings ▸ Output ▸
  Clipboard ▸ "Copyable text with images"** does the same idea sandbox-safely: it adds
  the text to the clipboard when you copy (paste the image anywhere, paste the text into
  an editor) and writes a `.txt` beside each image in a multi-size export. Handy for
  accessibility and for pairing a shared image with copy-pasteable output.
- Everything else about a snapshot still applies: background, padding, window title,
  annotations (arrow a failing assert, blur a secret), multi-size export, Brand Kit.

## Roadmap

Full-screen TUI capture shipped (the cell-buffer emulator described in
[Full-screen apps (TUIs)](#full-screen-apps-tuis)), with a fixed-height screen that
**scrolls** like a real terminal — so pagers (`less`, `man`, `bat`) and anything that
draws from the bottom line reconstruct correctly — plus scroll regions (`DECSTBM`), scroll
up/down, and line insert/delete. Still deferred, with the technical reason each is out:

- **Wide (double-width) characters.** CJK and emoji occupy two cells in a real terminal;
  the grid advances the cursor by one per scalar, so a frame dense with double-width
  glyphs can misalign. ASCII, box-drawing, and Powerline/Nerd glyphs (all single-width)
  are unaffected.
- **Explicit capture size.** The replay width is inferred from the content; passing the
  real `COLUMNS` (via `vgrab -w` / a `--terminal-width` flag) would make wraps pixel-exact.
