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
   color on and a styled image lands on your clipboard; a compact header identifies
   the Git project, current branch, and command, so the image still makes sense after
   it leaves your terminal. Paste it anywhere (⌘V).
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

Add **`--no-context`** when you want the original output-only image or the command line
contains sensitive arguments.

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

**Terminal ▸ ANSI palette ▸ Raw** (`--terminal-palette raw`) uses the standard xterm colors
instead. The card stays light or dark with the theme, so the header stays readable, and Raw
lifts one of the 16 base colors only where it would vanish on that card, such as bright white
on white. 256-color and truecolor values are drawn as written. Settings ▸ Style sets the default
for new captures, and a preset carries Raw only when saved from a terminal capture.

## Cursor

**Terminal ▸ Cursor** (`--terminal-cursor block|bar`) draws the cursor on the image and in rich
text. The default is Hidden, and plain text never includes it. Scrolling output gets the cursor
where the output ended; a full-screen app still running at the end of the capture gets it at its
real cell. A bar on a cell with its own background inverts that cell instead, because the cell
would paint over the bar. A cursor parked more than one row past the content, or beyond both the content's width and 80
columns, isn't drawn, so it can't grow the image. There is no cursor to draw when the program hid it (`ESC[?25l`), or when the frame comes
from a full-screen app that already exited, which is the usual `vgrab htop`. A share link of a
redacted capture holds only the final screen, so it opens without a cursor.

## Crop

**Terminal ▸ Crop rows** and **Crop columns** (`--terminal-crop-rows 6-18`,
`--terminal-crop-columns 1-80`) keep part of the final screen, as one `first-last` span; an
empty field keeps everything. The transcript is untouched, so clearing a field brings the rest
back. Rows keep their screen numbers: line numbers start at the first kept row, and highlighted
and redacted lines, including `--redact-lines`, still name screen rows. A wide character cut by
a column edge becomes a space, along with any mark or joiner attached to it, and a tab becomes
spaces.

Blur and spotlight boxes sit at fixed positions on the canvas, so the crop fields are off while
a capture has one, and `--blur-box` can't be combined with a crop.

Plain text, sidecars, rich text and share links carry only the kept cells, and an alternative
text draft counts only the kept rows. A cropped link keeps the colors but not link targets, and
opens without a cursor; with line numbers or highlights it places the kept rows under blank ones
so their numbers hold. A redacted link is plain text. A cursor outside the crop isn't drawn. The
header chips read the header, not the screen, so a crop leaves them alone.

## Prompt and context chips

In the inspector's **Header** section, a terminal capture lists its **Filename** and **Title**
as chips: `weather-app · main` becomes two labels and `$ htop` a prompt and a command. A title
without a `$` or `›` prompt is plain text and gets no command chip. Removing a chip, changing the
prompt, or using **Remove arguments** rewrites those two fields, plus any copy of their text in
the alternative text and window title, so the removed text leaves the image, share links and the
copied command. The chips read only those fields, never the transcript, and Edit ▸ Undo restores
a removal until the window closes.

Remove arguments reads the command the way a shell does and keeps only its name. It drops any
leading `VAR=value` and the command's directory, and clears the title when the first word doesn't
look like a command name, such as a URL or `user@host`. Text you reworded in the alternative text
stays as you wrote it, so check it before sharing. `vgrab -e` still opens without a header, so
the chips start empty until you fill those fields.

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
The one-click path accepts only regular UTF-8 startup files up to 1 MiB, verifies the
same open file before mutation, and appends only the helper block; it never reconstructs
or replaces the user's startup file.

(Install the CLI itself from Vitrine ▸ Settings ▸ General ▸ Command-line tool ▸
Install…. Basic `vgrab` capture is free. General `vitrine render`, `multi-size`, `batch`,
and `vpane` automation remain PRO.)

Then, in a new shell:

```sh
vgrab git status        # run it and copy a terminal image of its (colored) output
vgrab pytest            # no --color, no unbuffer, no pbcopy
vgrab cargo test
vgrab !!                # capture a command you already ran (re-runs the last one)
vgrab --no-context date # omit the project and command header
```

- **`vgrab <command>`** runs the command inside a pseudo-terminal (via the system
  `script`), so the program emits its colors automatically, captures the output, and
  copies the rendered image to the clipboard. The image header uses the Git root's
  directory name as the project label (falling back to the current directory), appends
  the current branch when Git reports one, and shows the executed command. Detached
  HEADs and non-Git directories simply omit the branch. Repository status is never read.
  Use it when you're *about to* run something. It returns the command's own exit
  status, so it composes (`vgrab make && …`), and **`vgrab -w 100 <command>`** pins
  the capture width: it exports `COLUMNS` for the program (best effort — tools that
  query the tty directly ignore it) and passes `--terminal-width` so Vitrine
  reconstructs wraps at exactly that width.
- **`--no-context`** omits the project and command header. Use it for a deliberately
  minimal image or whenever command arguments contain tokens, passwords, private paths,
  branch names, or other information that should not be shared.
- **Already ran something?** Recall it and prepend `vgrab` — `vgrab !!` (zsh/bash)
  expands to your last command and captures it; in any shell, press ↑ and add `vgrab`
  plus a space to the front. This re-runs the command, so it's ideal for read-only output (a
  `git log`, a test run); for slow or side-effecting commands, run them under `vgrab`
  in the first place.
- **`-e` / `--edit`** opens the captured output in Vitrine's **editor** instead of
  copying — to annotate, restyle, or change the theme before exporting.
  `vgrab -e git status` hands the output straight to a Vitrine window (nothing touches
  your clipboard).

### `vpane` — capture a tmux pane

Inside **tmux**, `vpane` captures what is *already on screen* without re-running
anything: it reads the pane's visible contents with colors (`tmux capture-pane -ep`)
and copies the rendered terminal image.

```sh
vpane                   # the current pane, exactly as it looks now
vpane %1                # any pane, by tmux target (%1, mysession:1.2, …)
vpane -e                # open the capture in Vitrine's editor instead
```

`vpane` is the complement to `vgrab`: use `vgrab` when you're about to run something,
`vpane` when the interesting output is already sitting in a tmux pane.

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

> Which escape sequences trigger the switch, why scrolling output is not merely a
> fallback, and how progress bars are collapsed without going through the emulator are
> documented in
> [ARCHITECTURE.md → Terminal rendering: two engines](ARCHITECTURE.md#terminal-rendering-two-engines).

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
vitrine render <input-file> --out <image> --sidecars all    # image + txt/md/html
vitrine render <input-file> --out <image> --terminal-palette raw   # only affects --language terminal
vitrine render <input-file> --out <image> --terminal-cursor block  # only affects --language terminal
vitrine render <input-file> --out <image> --terminal-crop-rows 6-18 --terminal-crop-columns 1-80
vitrine shell-init [zsh|bash|fish]            # print the helpers
```

`--copy` puts the rendered image on the clipboard; `--stdin` reads the source from a
pipe; `--edit` (`-e`) opens the source in Vitrine's editor instead of rendering — useful
to tweak before exporting; `--text-sidecar` writes a `.txt` of the output next to
`--out` (terminal escapes stripped), while `--sidecars all` adds the Markdown and HTML
embeds too. Each detects terminal output by its ANSI escapes when `--language` is
omitted. Since v1.3.0 `--edit` is free, including `vpane -e` (earlier downloads require
PRO for it), and is mutually exclusive with `--copy`/`--out`, sidecars,
and render-only styles. It only opens the editor; it does not unlock PRO image-output
automation.

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
  Vitrine bundles no Nerd Font — so there is nothing to license and no multi-megabyte asset —
  and falls back gracefully to the previous missing-glyph boxes when no Nerd Font is
  present. (Install any Nerd Font to light these up.)
- **Copyable text alongside the image.** From the command line, `--text-sidecar` writes
  a `.txt` next to the rendered image holding the output as selectable, greppable text —
  the terminal escapes stripped to the visible lines. `--markdown-sidecar`,
  `--html-sidecar`, or `--sidecars all` add README/web embeds with the same stripped
  visible text. In the app, **Settings ▸ Export ▸ Clipboard ▸ "Copyable text with
  images"** does the same idea sandbox-safely: it adds the text to the clipboard when
  you copy (paste the image anywhere, paste the text into an editor) and writes a `.txt`
  beside each image in a multi-size export. Handy for accessibility and for pairing a
  shared image with copy-pasteable output.
- Everything else about a snapshot still applies: background, padding, window title,
  annotations (arrow a failing assert, blur a secret), multi-size export, Brand Kit.

## Current capabilities

Full-screen TUI capture is feature-complete (the cell-buffer emulator described in
[Full-screen apps (TUIs)](#full-screen-apps-tuis)): a fixed-height screen that **scrolls**
like a real terminal — so pagers (`less`, `man`, `bat`) and anything that draws from the
bottom line reconstruct correctly — plus scroll regions (`DECSTBM`), scroll up/down, line
and character insert/delete (`ICH`/`DCH`/`ECH`), **wide (double-width) CJK/emoji characters
and combining marks**, and an explicit capture width.

- **Wide characters** advance the cursor two columns (combining marks zero), so a frame
  dense with CJK or emoji no longer drifts; ASCII, box-drawing, and Powerline/Nerd glyphs
  are single-width as before. One caveat is font-level: the image is laid out as flowed
  monospaced text, so the *pixel* alignment of a wide glyph still depends on your code
  font's CJK/emoji advance — the cell model is exact, the rendering is as good as the font.
- **Explicit capture width** — `vgrab -w <cols>` (or `vitrine render --terminal-width`)
  pins the replay width instead of inferring it from the content, so wraps match what you
  saw live.
