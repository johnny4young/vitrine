import Foundation

/// The `vitrine shell-init` integration: a `vgrab` shell function that turns terminal
/// output into a Vitrine image with zero color flags.
///
/// The whole strategy is **lean on the OS**: `/usr/bin/script` allocates a real
/// pseudo-terminal so any command emits its colors automatically, the colored bytes
/// land in a temp file, and the already-tested `vitrine render` turns that file into
/// an image. No PTY code lives in Swift, and nothing runs in the background — the
/// snippet only *defines* a function; it never re-execs or instruments your shell.
///
/// - `vgrab <cmd>` runs a command under `script` and copies a terminal image of its
///   (colored) output to the clipboard. To capture a command you already ran, recall
///   it (↑ or `!!`) and prepend `vgrab` — e.g. `vgrab !!`.
/// - `vpane [pane]` copies a terminal image of a tmux pane's visible contents
///   (colors included, via `tmux capture-pane -ep`) — the "capture what is already
///   on screen" complement to `vgrab`, with nothing re-run.
enum ShellInit {
    /// The shells the integration can emit. All three define `vgrab` as a plain
    /// function — no hooks, no re-exec, nothing always-on; only the function syntax
    /// differs between zsh/bash and fish.
    enum Shell: String {
        case zsh
        case bash
        case fish
    }

    /// Resolves the requested shell name, defaulting to the current `$SHELL`'s base
    /// name, then to zsh.
    static func resolveShell(_ argument: String?) -> Shell? {
        if let argument {
            return Shell(rawValue: argument)
        }
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        if shellPath.hasSuffix("/bash") { return .bash }
        if shellPath.hasSuffix("/fish") { return .fish }
        return .zsh
    }

    /// What the arguments after the `shell-init` subcommand resolve to.
    enum Invocation: Equatable {
        case help
        case snippet(Shell)
        case unknownShell(String)
        case extraArguments([String])
    }

    /// Classifies the arguments that follow `shell-init`. `--help`/`-h` wins in any
    /// position; otherwise at most one positional shell name is accepted, and anything
    /// extra is surfaced rather than silently ignored (so a typo like
    /// `shell-init zsh extra` is reported instead of quietly printing the zsh snippet).
    static func invocation(for arguments: [String]) -> Invocation {
        if arguments.contains("--help") || arguments.contains("-h") { return .help }
        if arguments.count > 1 { return .extraArguments(Array(arguments.dropFirst())) }
        guard let shell = resolveShell(arguments.first) else {
            return .unknownShell(arguments.first ?? "")
        }
        return .snippet(shell)
    }

    /// The snippet to `eval` from `~/.zshrc` (or `~/.bashrc` / `~/.config/fish/config.fish`).
    static func snippet(for shell: Shell) -> String {
        switch shell {
        case .zsh: zsh
        case .bash: bash
        case .fish: fish
        }
    }

    /// Usage shown for `vitrine shell-init --help`.
    static let usage = """
        vitrine shell-init [zsh|bash|fish] — print the shell integration.

        Add to your shell startup file (defaults to your $SHELL):

          # ~/.zshrc
          eval "$(vitrine shell-init zsh)"

        Then, in a new shell:
          vgrab <command>       run a command and copy a contextual terminal image
          vgrab --no-context …  omit the project and command header
          vpane [pane]          copy a terminal image of a tmux pane's visible contents

        To capture a command you already ran, recall it (↑ or !!) and prepend
        vgrab — e.g. `vgrab !!`. Inside tmux, `vpane` captures what is already on
        screen without re-running anything (pass a tmux target pane to capture
        another pane, e.g. `vpane %1`).
        """

    private static let zsh = """
        # >>> vitrine shell integration (zsh) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] [--no-context] <cmd…> — run a command under a
        # pseudo-terminal (so it emits color) and copy a terminal image of its output
        # to the clipboard. The image identifies the Git project (or current directory)
        # and command, plus the current branch when Git reports one; --no-context
        # produces an output-only image. Returns the command's own exit status (script -e).
        # -w/--width sets the capture width: it exports
        # COLUMNS for the command (best effort — tools that query the tty directly ignore
        # it) and passes --terminal-width so Vitrine reconstructs wraps at exactly that
        # width. -e/--edit opens the captured output in Vitrine's editor instead.
        #
        # To capture a command you already ran, recall it (↑ or !!) and prepend vgrab,
        # e.g. `vgrab !!`.
        vgrab() {
          emulate -L zsh
          local _vw="" _vshare="--copy" _vcontext=1
          while [[ "$1" == -* ]]; do
            case "$1" in
              -w|--width)
                if (( $# < 2 )) || [[ "$2" != <-> ]] || (( $2 < 1 || $2 > 1000 )); then
                  print -ru2 -- "usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]"
                  print -ru2 -- "vgrab: -w/--width needs a numeric column count (1-1000)"
                  return 2
                fi
                _vw="$2"; shift 2 ;;
              -e|--edit) _vshare="--edit"; shift ;;
              --no-context) _vcontext=0; shift ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if (( $# == 0 )); then
            print -ru2 -- "usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]"
            return 2
          fi
          local _vroot _vproject _vbranch _vlabel _vcmd
          _vroot="$(command git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" ||
            _vroot="$PWD"
          _vproject="${_vroot:t}"
          [[ -n "$_vproject" ]] || _vproject="/"
          _vbranch="$(command git -C "$PWD" branch --show-current 2>/dev/null)" ||
            _vbranch=""
          _vlabel="$_vproject"
          [[ -n "$_vbranch" ]] && _vlabel+=" · $_vbranch"
          _vcmd="${(j: :)${(q)@}}"
          local _vf
          _vf="$(mktemp -t vitrine-grab)" || return 1
          if [[ -n "$_vw" ]]; then
            COLUMNS="$_vw" script -qe "$_vf" "$@"
          else
            script -qe "$_vf" "$@"
          fi
          local _vc=$?
          local -a _vwarg _vcontextarg
          [[ -n "$_vw" ]] && _vwarg=(--terminal-width "$_vw")
          if (( _vcontext )) && [[ "$_vshare" != "--edit" ]]; then
            _vcontextarg=(--filename "$_vlabel" --title "$ $_vcmd")
          fi
          command vitrine render "$_vf" --language terminal "${_vwarg[@]}" "${_vcontextarg[@]}" "$_vshare"
          rm -f -- "$_vf"
          return $_vc
        }

        # vpane [-e] [target-pane] — copy a terminal image of a tmux pane's visible
        # contents (colors included, via `tmux capture-pane -ep`). Captures what is
        # already on screen without re-running anything: the current pane by default,
        # or any tmux target (e.g. `vpane %1`, `vpane mysession:1.2`). -e/--edit opens
        # the capture in Vitrine's editor instead of copying the image.
        vpane() {
          emulate -L zsh
          local _vshare="--copy"
          if [[ "$1" == "-e" || "$1" == "--edit" ]]; then _vshare="--edit"; shift; fi
          if ! command -v tmux >/dev/null 2>&1; then
            print -ru2 -- "vpane: tmux is not installed"
            return 2
          fi
          if [[ -z "${TMUX:-}" && $# -eq 0 ]]; then
            print -ru2 -- "vpane: not inside tmux — pass a target pane (e.g. vpane mysession:1.2)"
            return 2
          fi
          local _vf
          _vf="$(mktemp -t vitrine-pane)" || return 1
          if (( $# > 0 )); then
            tmux capture-pane -ep -t "$1" > "$_vf" || { rm -f -- "$_vf"; return 1; }
          else
            tmux capture-pane -ep > "$_vf" || { rm -f -- "$_vf"; return 1; }
          fi
          command vitrine render "$_vf" --language terminal "$_vshare"
          local _vc=$?
          rm -f -- "$_vf"
          return $_vc
        }
        # <<< vitrine shell integration (zsh) <<<
        """

    private static let bash = """
        # >>> vitrine shell integration (bash) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] [--no-context] <cmd…> — run a command under a
        # pseudo-terminal (so it emits color) and copy a terminal image of its output.
        # The image identifies the Git project (or current directory), command, and
        # current branch when Git reports one; --no-context produces an output-only image.
        # -w/--width sets the capture width
        # (exports COLUMNS for the command + passes --terminal-width so Vitrine
        # reconstructs wraps at that width); -e/--edit opens the output in Vitrine's editor.
        #
        # To capture a command you already ran, recall it (↑ or !!) and prepend vgrab,
        # e.g. `vgrab !!`.
        vgrab() {
          local _vw="" _vshare="--copy" _vcontext=1
          while [ "${1:0:1}" = "-" ]; do
            case "$1" in
              -w|--width)
                if [ "$#" -lt 2 ] || ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ] || [ "$2" -gt 1000 ]; then
                  printf 'usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]\n' >&2
                  printf 'vgrab: -w/--width needs a numeric column count (1-1000)\n' >&2
                  return 2
                fi
                _vw="$2"; shift 2 ;;
              -e|--edit) _vshare="--edit"; shift ;;
              --no-context) _vcontext=0; shift ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if [ "$#" -eq 0 ]; then
            printf 'usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]\\n' >&2
            return 2
          fi
          local _vroot _vproject _vbranch _vlabel _vcmd
          _vroot="$(command git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" ||
            _vroot="$PWD"
          _vproject="${_vroot##*/}"
          [ -n "$_vproject" ] || _vproject="/"
          _vbranch="$(command git -C "$PWD" branch --show-current 2>/dev/null)" ||
            _vbranch=""
          _vlabel="$_vproject"
          [ -n "$_vbranch" ] && _vlabel="$_vproject · $_vbranch"
          printf -v _vcmd '%q ' "$@"
          _vcmd="${_vcmd% }"
          local _vf
          _vf="$(mktemp -t vitrine-grab)" || return 1
          if [ -n "$_vw" ]; then
            COLUMNS="$_vw" script -qe "$_vf" "$@"
          else
            script -qe "$_vf" "$@"
          fi
          local _vc=$?
          local _vwarg=() _vcontextarg=()
          [ -n "$_vw" ] && _vwarg=(--terminal-width "$_vw")
          if [ "$_vcontext" -eq 1 ] && [ "$_vshare" != "--edit" ]; then
            _vcontextarg=(--filename "$_vlabel" --title "$ $_vcmd")
          fi
          command vitrine render "$_vf" --language terminal "${_vwarg[@]}" "${_vcontextarg[@]}" "$_vshare"
          rm -f -- "$_vf"
          return $_vc
        }

        # vpane [-e] [target-pane] — copy a terminal image of a tmux pane's visible
        # contents (colors included, via `tmux capture-pane -ep`). Captures what is
        # already on screen without re-running anything: the current pane by default,
        # or any tmux target (e.g. `vpane %1`, `vpane mysession:1.2`). -e/--edit opens
        # the capture in Vitrine's editor instead of copying the image.
        vpane() {
          local _vshare="--copy"
          if [ "$1" = "-e" ] || [ "$1" = "--edit" ]; then _vshare="--edit"; shift; fi
          if ! command -v tmux >/dev/null 2>&1; then
            printf 'vpane: tmux is not installed\\n' >&2
            return 2
          fi
          if [ -z "${TMUX:-}" ] && [ "$#" -eq 0 ]; then
            printf 'vpane: not inside tmux — pass a target pane (e.g. vpane mysession:1.2)\\n' >&2
            return 2
          fi
          local _vf
          _vf="$(mktemp -t vitrine-pane)" || return 1
          if [ "$#" -gt 0 ]; then
            tmux capture-pane -ep -t "$1" > "$_vf" || { rm -f -- "$_vf"; return 1; }
          else
            tmux capture-pane -ep > "$_vf" || { rm -f -- "$_vf"; return 1; }
          fi
          command vitrine render "$_vf" --language terminal "$_vshare"
          local _vc=$?
          rm -f -- "$_vf"
          return $_vc
        }
        # <<< vitrine shell integration (bash) <<<
        """

    private static let fish = """
        # >>> vitrine shell integration (fish) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] [--no-context] <cmd…> — run a command under a
        # pseudo-terminal (so it emits color) and copy a terminal image of its output.
        # The image identifies the Git project (or current directory), command, and
        # current branch when Git reports one; --no-context produces an output-only image.
        # -w/--width sets the capture width
        # (exports COLUMNS for the command + passes --terminal-width so Vitrine
        # reconstructs wraps at that width); -e/--edit opens the output in Vitrine's editor.
        #
        # To capture a command you already ran, recall it (↑) and prepend vgrab.
        function vgrab --description 'run a command and copy a terminal image of its output'
            set -l _vw ''
            set -l _vshare '--copy'
            set -l _vcontext 1
            while set -q argv[1]; and string match -qr -- '^-' $argv[1]
                switch $argv[1]
                    case -w --width
                        if test (count $argv) -lt 2
                            echo "usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]" >&2
                            echo "vgrab: -w/--width needs a numeric column count (1-1000)" >&2
                            return 2
                        else if not string match -qr '^[0-9]+$' -- $argv[2]
                            echo "usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]" >&2
                            echo "vgrab: -w/--width needs a numeric column count (1-1000)" >&2
                            return 2
                        else if test $argv[2] -lt 1; or test $argv[2] -gt 1000
                            echo "usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]" >&2
                            echo "vgrab: -w/--width needs a numeric column count (1-1000)" >&2
                            return 2
                        end
                        set _vw $argv[2]
                        set -e argv[1 2]
                    case -e --edit
                        set _vshare '--edit'
                        set -e argv[1]
                    case --no-context
                        set _vcontext 0
                        set -e argv[1]
                    case --
                        set -e argv[1]
                        break
                    case '*'
                        break
                end
            end
            if test (count $argv) -eq 0
                echo "usage: vgrab [-w cols] [-e] [--no-context] <command> [args…]" >&2
                return 2
            end
            set -l _vroot (command git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)
            or set _vroot "$PWD"
            set -l _vproject (string replace -r '^.*/' '' -- "$_vroot")
            test -n "$_vproject"; or set _vproject /
            set -l _vbranch (command git -C "$PWD" branch --show-current 2>/dev/null)
            set -l _vlabel "$_vproject"
            if test -n "$_vbranch"
                set _vlabel "$_vproject · $_vbranch"
            end
            set -l _vcmd (string escape -- $argv | string join ' ')
            set -l _vf (mktemp -t vitrine-grab); or return 1
            if test -n "$_vw"
                env COLUMNS=$_vw script -qe $_vf $argv
            else
                script -qe $_vf $argv
            end
            set -l _vc $status
            set -l _vwarg
            if test -n "$_vw"
                set _vwarg --terminal-width $_vw
            end
            set -l _vcontextarg
            if test $_vcontext -eq 1; and test "$_vshare" != '--edit'
                set _vcontextarg --filename "$_vlabel" --title "$ $_vcmd"
            end
            command vitrine render $_vf --language terminal $_vwarg $_vcontextarg $_vshare
            rm -f -- $_vf
            return $_vc
        end

        # vpane [-e] [target-pane] — copy a terminal image of a tmux pane's visible
        # contents (colors included, via `tmux capture-pane -ep`). Captures what is
        # already on screen without re-running anything: the current pane by default,
        # or any tmux target (e.g. `vpane %1`). -e/--edit opens the capture in
        # Vitrine's editor instead of copying the image.
        function vpane --description 'copy a terminal image of a tmux pane'
            set -l _vshare '--copy'
            if set -q argv[1]; and contains -- $argv[1] -e --edit
                set _vshare '--edit'
                set -e argv[1]
            end
            if not command -q tmux
                echo "vpane: tmux is not installed" >&2
                return 2
            end
            if not set -q TMUX; and test (count $argv) -eq 0
                echo "vpane: not inside tmux — pass a target pane (e.g. vpane mysession:1.2)" >&2
                return 2
            end
            set -l _vf (mktemp -t vitrine-pane); or return 1
            if test (count $argv) -gt 0
                tmux capture-pane -ep -t $argv[1] > $_vf
            else
                tmux capture-pane -ep > $_vf
            end
            if test $status -ne 0
                rm -f -- $_vf
                return 1
            end
            command vitrine render $_vf --language terminal $_vshare
            set -l _vc $status
            rm -f -- $_vf
            return $_vc
        end
        # <<< vitrine shell integration (fish) <<<
        """
}
