import Foundation

/// The `vitrine shell-init` integration: shell functions that turn terminal output
/// into a Vitrine image with zero color flags.
///
/// The whole strategy is **lean on the OS**: `/usr/bin/script` allocates a real
/// pseudo-terminal so any command emits its colors automatically, the colored bytes
/// land in a temp file, and the already-tested `vitrine render` turns that file into
/// an image. No PTY code lives in Swift.
///
/// - `vgrab <cmd>` runs a command under `script` and copies a terminal image of its
///   (colored) output to the clipboard — for output you are about to produce.
/// - `vlast` shares the **last** command you already ran, without re-running it. That
///   needs a passive recorder, so the snippet re-execs the interactive shell under
///   `script` (guarded, once) and uses `preexec`/`precmd` hooks to keep the last
///   command's output sliced into a small file.
enum ShellInit {
    /// The shells the integration can emit. All three ship `vgrab` and the passive
    /// `vlast` recorder; only the hook mechanism differs (zsh `add-zsh-hook`, bash
    /// `DEBUG` trap + `PROMPT_COMMAND`, fish `fish_preexec`/`fish_postexec` events).
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
          vlast             copy a terminal image of the LAST command you ran
        """

    private static let zsh = """
        # >>> vitrine shell integration (zsh) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] <cmd…> — run a command under a pseudo-terminal (so it
        # emits color) and copy a terminal image of its output to the clipboard. Returns
        # the command's own exit status (script -e). -w/--width sets COLUMNS for it (a
        # best effort: tools that query the tty size directly ignore it). -e/--edit opens
        # the captured output in Vitrine's editor (to annotate/restyle) instead of copying.
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
          command vitrine render "$_vf" --language terminal "$_vshare"
          rm -f -- "$_vf"
          return $_vc
        }

        # Passive recorder: re-exec this interactive shell under `script` so the colored
        # stream is captured, letting `vlast` share an already-run command with no
        # re-run. Guarded to run exactly once; remove these lines to disable it.
        if [[ -o interactive && -z "${VITRINE_REC:-}" && -t 1 ]] \\
             && command -v script >/dev/null 2>&1 && command -v vitrine >/dev/null 2>&1; then
          if VITRINE_REC="$(mktemp -t vitrine-session)" \\
               && VITRINE_LAST="$(mktemp -t vitrine-last)"; then
            export VITRINE_REC VITRINE_LAST
            exec script -q "$VITRINE_REC" "$SHELL"
          fi
        fi

        # In the recorded shell: mark each command's output region and slice the last
        # one into $VITRINE_LAST (a tiny file `vlast` renders).
        if [[ -n "${VITRINE_REC:-}" ]]; then
          autoload -Uz add-zsh-hook 2>/dev/null
          _vitrine_preexec() { _VITRINE_OFFSET=$(wc -c < "$VITRINE_REC" 2>/dev/null || print 0) }
          _vitrine_precmd() {
            [[ -n "${_VITRINE_OFFSET:-}" && -f "$VITRINE_REC" ]] || return 0
            tail -c "+$(( _VITRINE_OFFSET + 1 ))" "$VITRINE_REC" > "$VITRINE_LAST" 2>/dev/null
            unset _VITRINE_OFFSET
          }
          add-zsh-hook preexec _vitrine_preexec 2>/dev/null
          add-zsh-hook precmd _vitrine_precmd 2>/dev/null
        fi

        # vlast [-e] — copy a terminal image of the last command's output (no re-run).
        # -e/--edit opens it in Vitrine's editor instead of copying.
        vlast() {
          emulate -L zsh
          local _vshare="--copy"
          [[ "$1" == "-e" || "$1" == "--edit" ]] && { _vshare="--edit"; shift }
          if [[ -z "${VITRINE_LAST:-}" || ! -s "$VITRINE_LAST" ]]; then
            print -ru2 -- "vlast: nothing recorded yet — run a command first (the recorder starts in a new shell after install)."
            return 1
          fi
          command vitrine render "$VITRINE_LAST" --language terminal "$_vshare" "$@"
        }
        # <<< vitrine shell integration (zsh) <<<
        """

    private static let bash = """
        # >>> vitrine shell integration (bash) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] <cmd…> — run a command under a pseudo-terminal (so it
        # emits color) and copy a terminal image of its output. -w/--width sets COLUMNS;
        # -e/--edit opens the captured output in Vitrine's editor instead of copying.
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
          command vitrine render "$_vf" --language terminal "$_vshare"
          rm -f -- "$_vf"
          return $_vc
        }

        # Passive recorder: re-exec this interactive shell under `script` so the colored
        # stream is captured, letting `vlast` share an already-run command with no
        # re-run. Guarded to run exactly once; remove these lines to disable it.
        if [[ $- == *i* && -z "${VITRINE_REC:-}" && -t 1 ]] \\
             && command -v script >/dev/null 2>&1 && command -v vitrine >/dev/null 2>&1; then
          if VITRINE_REC="$(mktemp -t vitrine-session)" \\
               && VITRINE_LAST="$(mktemp -t vitrine-last)"; then
            export VITRINE_REC VITRINE_LAST
            exec script -q "$VITRINE_REC" "$SHELL"
          fi
        fi

        # In the recorded shell: a DEBUG trap (≈ preexec) marks the output offset once
        # per prompt, and PROMPT_COMMAND (≈ precmd, chained last) slices the last
        # command's output into $VITRINE_LAST. The `_vitrine_armed` guard keeps the
        # trap from re-marking on every sub-command.
        if [[ -n "${VITRINE_REC:-}" ]]; then
          _vitrine_armed=""
          _vitrine_preexec() {
            [[ -n "${COMP_LINE:-}" ]] && return  # skip completion
            [[ -n "$_vitrine_armed" ]] && return  # once per prompt
            _vitrine_armed=1
            _VITRINE_OFFSET=$(wc -c < "$VITRINE_REC" 2>/dev/null || echo 0)
          }
          _vitrine_precmd() {
            if [[ -n "${_VITRINE_OFFSET:-}" && -f "$VITRINE_REC" ]]; then
              tail -c "+$(( _VITRINE_OFFSET + 1 ))" "$VITRINE_REC" > "$VITRINE_LAST" 2>/dev/null
              unset _VITRINE_OFFSET
            fi
            _vitrine_armed=""
          }
          trap '_vitrine_preexec' DEBUG
          case "${PROMPT_COMMAND:-}" in
            *_vitrine_precmd*) ;;
            *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_vitrine_precmd" ;;
          esac
        fi

        # vlast [-e] — copy a terminal image of the last command's output (no re-run).
        # -e/--edit opens it in Vitrine's editor instead of copying.
        vlast() {
          local _vshare="--copy"
          [[ "$1" == "-e" || "$1" == "--edit" ]] && { _vshare="--edit"; shift; }
          if [[ -z "${VITRINE_LAST:-}" || ! -s "$VITRINE_LAST" ]]; then
            printf 'vlast: nothing recorded yet — run a command first (the recorder starts in a new shell after install).\\n' >&2
            return 1
          fi
          command vitrine render "$VITRINE_LAST" --language terminal "$_vshare" "$@"
        }
        # <<< vitrine shell integration (bash) <<<
        """

    private static let fish = """
        # >>> vitrine shell integration (fish) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] [-e] <cmd…> — run a command under a pseudo-terminal (so it
        # emits color) and copy a terminal image of its output. -w/--width sets COLUMNS;
        # -e/--edit opens the captured output in Vitrine's editor instead of copying.
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
            command vitrine render $_vf --language terminal $_vshare
            rm -f -- $_vf
            return $_vc
        end

        # Passive recorder: re-exec this interactive shell under `script` so the colored
        # stream is captured, letting `vlast` share an already-run command with no
        # re-run. Guarded to run exactly once; remove these lines to disable it.
        if status is-interactive; and not set -q VITRINE_REC; and isatty stdout
            and command -q script; and command -q vitrine
            set -l _vrec (mktemp -t vitrine-session)
            set -l _vlast (mktemp -t vitrine-last)
            if test -n "$_vrec"; and test -n "$_vlast"
                set -gx VITRINE_REC $_vrec
                set -gx VITRINE_LAST $_vlast
                exec script -q $VITRINE_REC fish
            end
        end

        # In the recorded shell: fish's native preexec/postexec events mark the output
        # offset before each command and slice the last one into $VITRINE_LAST.
        if set -q VITRINE_REC
            function _vitrine_preexec --on-event fish_preexec
                set -g _VITRINE_OFFSET (wc -c < $VITRINE_REC 2>/dev/null | string trim)
            end
            function _vitrine_precmd --on-event fish_postexec
                if set -q _VITRINE_OFFSET; and test -n "$_VITRINE_OFFSET"; and test -f "$VITRINE_REC"
                    tail -c +(math "$_VITRINE_OFFSET + 1") $VITRINE_REC > $VITRINE_LAST 2>/dev/null
                    set -e _VITRINE_OFFSET
                end
            end
        end

        # vlast [-e] — copy a terminal image of the last command's output (no re-run).
        # -e/--edit opens it in Vitrine's editor instead of copying.
        function vlast --description 'copy a terminal image of the last command output'
            set -l _vshare '--copy'
            if test "$argv[1]" = '-e'; or test "$argv[1]" = '--edit'
                set _vshare '--edit'
                set -e argv[1]
            end
            if not set -q VITRINE_LAST; or not test -s "$VITRINE_LAST"
                echo "vlast: nothing recorded yet — run a command first (the recorder starts in a new shell after install)." >&2
                return 1
            end
            command vitrine render $VITRINE_LAST --language terminal $_vshare $argv
        end
        # <<< vitrine shell integration (fish) <<<
        """
}
