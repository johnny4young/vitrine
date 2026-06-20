# Terminal / ANSI output → image

Vitrine renders **terminal output** — anything with ANSI color escape codes (`git`,
test runners, `ls --color`, build logs) — as a styled terminal image. The colors come
from the escape codes themselves (standard 16-color, 256-color, and 24-bit truecolor)
with bold / dim / italic / underline / inverse, on a dark terminal background.

It is a first-class **Terminal** language: pasting, dropping a file, quick-capturing,
or `vitrine render … --language terminal` all work, and Vitrine auto-detects terminal
output by its escape codes (they override the file extension, so a `.log`/`.txt` of
colored output is recognized too).

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
  something.
- **`vlast`** shares the command you *already* ran. Because the integration passively
  records your session, the colored output of the last command is already captured — so
  `vlast` renders it instantly, with no re-run and no side effects.

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
vitrine shell-init [zsh|bash]                 # print the helpers
```

`--copy` puts the rendered image on the clipboard; `--stdin` reads the source from a
pipe. Both detect terminal output by its ANSI escapes when `--language` is omitted.

## Notes

- Vitrine strips the non-color escape sequences (cursor moves, screen clears, OSC
  window titles, progress-bar carriage returns) so the static image shows clean,
  final lines.
- Everything else about a snapshot still applies: background, padding, window title,
  annotations (arrow a failing assert, blur a secret), multi-size export, Brand Kit.
