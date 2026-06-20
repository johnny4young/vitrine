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
    /// The shells the integration can emit. `zsh` is fully supported; `bash` ships
    /// `vgrab` (portable) and notes that the passive recorder is zsh-only for now.
    enum Shell: String {
        case zsh
        case bash
    }

    /// Resolves the requested shell name, defaulting to the current `$SHELL`'s base
    /// name, then to zsh.
    static func resolveShell(_ argument: String?) -> Shell? {
        if let argument {
            return Shell(rawValue: argument)
        }
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        if shellPath.hasSuffix("/bash") { return .bash }
        return .zsh
    }

    /// The snippet to `eval` from `~/.zshrc` (or `~/.bashrc`).
    static func snippet(for shell: Shell) -> String {
        switch shell {
        case .zsh: zsh
        case .bash: bash
        }
    }

    /// Usage shown for `vitrine shell-init --help`.
    static let usage = """
        vitrine shell-init [zsh|bash] — print the shell integration.

        Add to your shell startup file (defaults to your $SHELL):

          # ~/.zshrc
          eval "$(vitrine shell-init zsh)"

        Then, in a new shell:
          vgrab <command>   run a command and copy a terminal image of its output
          vlast             copy a terminal image of the LAST command you ran (zsh)
        """

    private static let zsh = """
        # >>> vitrine shell integration (zsh) >>>
        # Turn terminal output into a Vitrine image. Docs: vitrine shell-init --help

        # vgrab [-w cols] <cmd…> — run a command under a pseudo-terminal (so it emits
        # color) and copy a terminal image of its output to the clipboard. Returns the
        # command's own exit status (script -e). -w/--width sets COLUMNS for it (a
        # best effort: tools that query the tty size directly ignore it).
        vgrab() {
          emulate -L zsh
          local _vw=""
          while [[ "$1" == -* ]]; do
            case "$1" in
              -w|--width) _vw="$2"; shift 2 ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if (( $# == 0 )); then
            print -ru2 -- "usage: vgrab [-w cols] <command> [args…]"
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
          command vitrine render "$_vf" --language terminal --copy
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

        # vlast — copy a terminal image of the last command's output (no re-run).
        vlast() {
          emulate -L zsh
          if [[ -z "${VITRINE_LAST:-}" || ! -s "$VITRINE_LAST" ]]; then
            print -ru2 -- "vlast: nothing recorded yet — run a command first (the recorder starts in a new shell after install)."
            return 1
          fi
          command vitrine render "$VITRINE_LAST" --language terminal --copy "$@"
        }
        # <<< vitrine shell integration (zsh) <<<
        """

    private static let bash = """
        # >>> vitrine shell integration (bash) >>>
        # `vgrab` works in bash; the passive `vlast` recorder is zsh-only for now.

        vgrab() {
          local _vw=""
          while [ "${1:0:1}" = "-" ]; do
            case "$1" in
              -w|--width) _vw="$2"; shift 2 ;;
              --) shift; break ;;
              *) break ;;
            esac
          done
          if [ "$#" -eq 0 ]; then
            printf 'usage: vgrab [-w cols] <command> [args…]\\n' >&2
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
          command vitrine render "$_vf" --language terminal --copy
          rm -f -- "$_vf"
          return $_vc
        }
        # <<< vitrine shell integration (bash) <<<
        """
}
