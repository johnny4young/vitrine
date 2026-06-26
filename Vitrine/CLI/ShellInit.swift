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
          vgrab <command>   run a command and copy a terminal image of its output

        To capture a command you already ran, recall it (↑ or !!) and prepend
        vgrab — e.g. `vgrab !!`.
        """

    private static let zsh = """
        # >>> vitrine shell integration (zsh) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] <cmd…> — run a command under a pseudo-terminal (so it
        # emits color) and copy a terminal image of its output to the clipboard. Returns
        # the command's own exit status (script -e). -w/--width sets the capture width: it
        # exports COLUMNS for the command (best effort — tools that query the tty directly
        # ignore it) and passes --terminal-width so Vitrine reconstructs wraps at exactly
        # that width. -e/--edit opens the captured output in Vitrine's editor instead.
        #
        # To capture a command you already ran, recall it (↑ or !!) and prepend vgrab,
        # e.g. `vgrab !!`.
        vgrab() {
          emulate -L zsh
          local _vw="" _vshare="--copy"
          while [[ "$1" == -* ]]; do
            case "$1" in
              -w|--width) _vw="$2"; shift 2 ;;
              -e|--edit) _vshare="--edit"; shift ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if (( $# == 0 )); then
            print -ru2 -- "usage: vgrab [-w cols] [-e] <command> [args…]"
            return 2
          fi
          local _vf
          _vf="$(mktemp -t vitrine-grab)" || return 1
          if [[ -n "$_vw" ]]; then
            COLUMNS="$_vw" script -qe "$_vf" "$@"
          else
            script -qe "$_vf" "$@"
          fi
          local _vc=$?
          local -a _vwarg
          [[ -n "$_vw" ]] && _vwarg=(--terminal-width "$_vw")
          command vitrine render "$_vf" --language terminal "${_vwarg[@]}" "$_vshare"
          rm -f -- "$_vf"
          return $_vc
        }
        # <<< vitrine shell integration (zsh) <<<
        """

    private static let bash = """
        # >>> vitrine shell integration (bash) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] <cmd…> — run a command under a pseudo-terminal (so it
        # emits color) and copy a terminal image of its output. -w/--width sets the capture
        # width (exports COLUMNS for the command + passes --terminal-width so Vitrine
        # reconstructs wraps at that width); -e/--edit opens the output in Vitrine's editor.
        #
        # To capture a command you already ran, recall it (↑ or !!) and prepend vgrab,
        # e.g. `vgrab !!`.
        vgrab() {
          local _vw="" _vshare="--copy"
          while [ "${1:0:1}" = "-" ]; do
            case "$1" in
              -w|--width) _vw="$2"; shift 2 ;;
              -e|--edit) _vshare="--edit"; shift ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if [ "$#" -eq 0 ]; then
            printf 'usage: vgrab [-w cols] [-e] <command> [args…]\\n' >&2
            return 2
          fi
          local _vf
          _vf="$(mktemp -t vitrine-grab)" || return 1
          if [ -n "$_vw" ]; then
            COLUMNS="$_vw" script -qe "$_vf" "$@"
          else
            script -qe "$_vf" "$@"
          fi
          local _vc=$?
          local _vwarg=()
          [ -n "$_vw" ] && _vwarg=(--terminal-width "$_vw")
          command vitrine render "$_vf" --language terminal "${_vwarg[@]}" "$_vshare"
          rm -f -- "$_vf"
          return $_vc
        }
        # <<< vitrine shell integration (bash) <<<
        """

    private static let fish = """
        # >>> vitrine shell integration (fish) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] <cmd…> — run a command under a pseudo-terminal (so it
        # emits color) and copy a terminal image of its output. -w/--width sets the capture
        # width (exports COLUMNS for the command + passes --terminal-width so Vitrine
        # reconstructs wraps at that width); -e/--edit opens the output in Vitrine's editor.
        #
        # To capture a command you already ran, recall it (↑) and prepend vgrab.
        function vgrab --description 'run a command and copy a terminal image of its output'
            set -l _vw ''
            set -l _vshare '--copy'
            while set -q argv[1]; and string match -qr -- '^-' $argv[1]
                switch $argv[1]
                    case -w --width
                        set _vw $argv[2]
                        set -e argv[1 2]
                    case -e --edit
                        set _vshare '--edit'
                        set -e argv[1]
                    case --
                        set -e argv[1]
                        break
                    case '*'
                        break
                end
            end
            if test (count $argv) -eq 0
                echo "usage: vgrab [-w cols] [-e] <command> [args…]" >&2
                return 2
            end
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
            command vitrine render $_vf --language terminal $_vwarg $_vshare
            rm -f -- $_vf
            return $_vc
        end
        # <<< vitrine shell integration (fish) <<<
        """
}
