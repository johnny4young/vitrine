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
2. **`vlast`** — already ran it? Don't re-run. `vlast` shares the **last** command's
   output (the integration recorded it as it scrolled past), with no side effects.
3. **Paste or drop** — paste colored output straight into Vitrine (⌘V), or drop a
   `.log` / `.txt` file; it auto-detects terminal output and styles it.

Add **`-e`** to either (`vgrab -e <command>`, `vlast -e`) to open the output in Vitrine's
editor — to annotate or restyle before exporting — instead of copying an image.

`vgrab` and `vlast` need the one-time shell hook (`eval "$(vitrine shell-init zsh)"`,
below). Paste / drop and the `--stdin` pipe need no setup.

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

## `vgrab` and `vlast` (recommended)

Install the integration once:

```sh
# ~/.zshrc
eval "$(vitrine shell-init zsh)"
```

(Install the CLI itself from Vitrine ▸ Settings ▸ General ▸ Command-line tool ▸
Install…. The helpers require Vitrine PRO, like all CLI rendering.)

Then, in a new shell:

```sh
vgrab git status        # run it and copy a terminal image of its (colored) output
vgrab pytest            # no --color, no unbuffer, no pbcopy
vgrab cargo test
vlast                   # share the LAST command you already ran — without re-running it
```

- **`vgrab <command>`** runs the command inside a pseudo-terminal (via the system
  `script`), so the program emits its colors automatically, captures the output, and
  copies the rendered image to the clipboard. Use it when you're *about to* run
  something. It returns the command's own exit status, so it composes
  (`vgrab make && …`), and **`vgrab -w 100 <command>`** sets the capture width
  (`COLUMNS`) so wide output like `git log --graph` wraps consistently — a best effort,
  since tools that query the terminal size directly ignore it.
- **`vlast`** shares the command you *already* ran. Because the integration passively
  records your session, the colored output of the last command is already captured — so
  `vlast` renders it instantly, with no re-run and no side effects.
- **`-e` / `--edit`** on either helper opens the captured output in Vitrine's **editor**
  instead of copying — to annotate, restyle, or change the theme before exporting.
  `vgrab -e git status` and `vlast -e` hand the output straight to a Vitrine window
  (nothing touches your clipboard).

### How the passive recorder works (and its one trade-off)

To recover the color of an already-run command, it had to be captured *as it ran* —
there's no way to re-colorize plain text after the fact. So `shell-init` re-execs your
interactive shell under `script` (once, guarded) to record the colored stream your
terminal receives, and uses `preexec`/`precmd` hooks to keep the **last** command's
output sliced into a tiny file that `vlast` renders.

Trade-off, stated plainly:

- It only records sessions started **after** you add the line — there's no magic for a
  session that was already running.
- Your interactive shell runs under `script` while the recorder is on. It's
  transparent in normal use; remove the recorder block from the snippet (or the whole
  `eval` line) to disable it. `vgrab` works without the recorder.

`bash` ships `vgrab` today; the passive `vlast` recorder is zsh-only for now.

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
vitrine shell-init [zsh|bash]                 # print the helpers
```

`--copy` puts the rendered image on the clipboard; `--stdin` reads the source from a
pipe; `--edit` (`-e`) opens the source in Vitrine's editor instead of rendering — useful
to tweak before exporting. Each detects terminal output by its ANSI escapes when
`--language` is omitted. `--edit` is mutually exclusive with `--copy`/`--out`.

## Notes

- Vitrine strips the non-color escape sequences (cursor moves, screen clears, OSC
  window titles, progress-bar carriage returns) so the static image shows clean,
  final lines.
- Everything else about a snapshot still applies: background, padding, window title,
  annotations (arrow a failing assert, blur a secret), multi-size export, Brand Kit.

## Roadmap

Deferred, with the technical reason each is not in the first cut:

- **Nerd Font / Powerline / icon glyphs.** Modern prompts (`starship`), `eza --icons`,
  and Powerline separators use glyphs from the Private Use Area that the bundled
  JetBrains Mono lacks, so they render as missing boxes. The fix is a font **cascade
  list** (`kCTFontCascadeListAttribute`) with a bundled *Symbols Nerd Font* as the
  fallback — it needs shipping that font asset (size + OFL license review). Box-drawing
  characters already render (JetBrains Mono includes them).
- **Full terminal emulation (TUIs, progress bars, redraws).** The current renderer is
  line-oriented: it strips cursor-movement sequences and collapses carriage returns, so
  line-based output (`git`, test runners, `ls`) is faithful, but full-screen apps
  (`htop`, `vim`) and in-place progress bars are not. Capturing the *final screen
  state* needs a small VT/grid emulator (cursor positioning into a cell buffer, à la
  `pyte`), which is a separate, larger component.
- **One-click shell-init install.** A Settings button that appends the `eval` line to
  `~/.zshrc`. The App Store build is sandboxed and cannot write arbitrary files, so the
  interim is a "Copy setup line" button; auto-install would ship in the direct-download
  build or behind a user-selected file grant.
- **`vlast` for bash / fish, and native terminal integrations.** Today the passive
  recorder is zsh-only. bash needs `bash-preexec`/`DEBUG`-trap equivalents; fish needs
  its event hooks. iTerm2 / kitty / WezTerm expose the *last command's* output via their
  own shell integration, which would let `vlast` skip the `exec script` re-exec entirely
  on those terminals (less invasive).
- **OSC 8 hyperlinks** (style the linked text) and a **copyable-text sidecar** (ship the
  raw output alongside the image for accessibility / easy copy) — small, additive.
