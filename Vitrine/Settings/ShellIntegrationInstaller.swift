import AppKit
import Foundation

/// Adds the `vgrab` / `vlast` shell helpers to the user's shell startup file
/// (the one-click counterpart of pasting `eval "$(vitrine shell-init zsh)"` by
/// hand), surfaced as a Settings ▸ General row beside the CLI installer (CS-033).
///
/// The app is sandboxed, so it cannot write `~/.zshrc` on its own: the user
/// picks their startup file through the open panel (the powerbox grants
/// read-write to exactly that file), and the eval line is appended inside the
/// grant. The append is idempotent — a file that already activates the
/// integration is left untouched — and a refusal falls back to a copyable
/// Terminal command, the honest sandbox-true behavior.
///
/// Mirrors `CLIToolInstaller`; the integration depends on the `vitrine` command,
/// so the Settings row appears alongside it.
enum ShellIntegrationInstaller {
    /// The line a startup file evaluates to load the helpers. zsh/bash use
    /// `eval "$(…)"`; fish has no `$(…)` and sources a pipe instead
    /// (`vitrine shell-init fish | source`).
    static func evalLine(for shell: ShellInit.Shell) -> String {
        switch shell {
        case .zsh, .bash: "eval \"$(vitrine shell-init \(shell.rawValue))\""
        case .fish: "vitrine shell-init fish | source"
        }
    }

    /// The commented block appended to the startup file: a header so the user can
    /// find (and remove) it later, then the eval line.
    static func block(for shell: ShellInit.Shell) -> String {
        "# Vitrine shell integration (vgrab / vlast)\n\(evalLine(for: shell))"
    }

    /// The default startup file for `shell` under the user's home directory
    /// (`~/.zshrc` or `~/.bashrc`). Parameterized so tests can point it at a
    /// temporary home.
    static func startupFile(
        for shell: ShellInit.Shell,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        switch shell {
        case .zsh: home.appendingPathComponent(".zshrc")
        case .bash: home.appendingPathComponent(".bashrc")
        case .fish: home.appendingPathComponent(".config/fish/config.fish")
        }
    }

    /// Whether `contents` already activates the integration. Keyed on the stable
    /// `vitrine shell-init` marker (present in any eval line, zsh or bash, and in
    /// a hand-pasted variant) so the install never appends a duplicate.
    static func isInstalled(in contents: String) -> Bool {
        contents.contains("vitrine shell-init")
    }

    /// The Terminal equivalent of the install, shown (and copyable) when the file
    /// can't be granted. `>>` appends and creates the file if it is missing; the
    /// single quotes keep the `$(…)` literal so the shell expands it at startup,
    /// not now.
    static func terminalCommand(for shell: ShellInit.Shell) -> String {
        let file: String
        switch shell {
        case .zsh: file = "~/.zshrc"
        case .bash: file = "~/.bashrc"
        case .fish: file = "~/.config/fish/config.fish"
        }
        return "echo '\(evalLine(for: shell))' >> \(file)"
    }

    /// The result of an install attempt into a powerbox-granted file.
    enum InstallOutcome: Equatable {
        case installed(URL)
        /// The file already activates the integration — a no-op, surfaced so the
        /// UI can say so rather than silently appearing to do nothing.
        case alreadyInstalled(URL)
        case failed(String)
    }

    /// Appends the integration block to `file` (a startup file the user just
    /// granted through the open panel), idempotently. Reads the current contents
    /// first: if the integration is already present it is a no-op; otherwise the
    /// block is appended, inserting a leading newline only when the file does not
    /// already end in one so the eval line never glues onto the previous line.
    ///
    /// The write is **non-atomic on purpose**: a user-selected file grant covers
    /// that file, not its directory, so an atomic write (temp file + rename in the
    /// parent) would be refused — writing the bytes in place stays within the grant.
    static func install(
        _ shell: ShellInit.Shell, into file: URL, fileManager: FileManager = .default
    ) -> InstallOutcome {
        let didScope = file.startAccessingSecurityScopedResource()
        defer { if didScope { file.stopAccessingSecurityScopedResource() } }

        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        if isInstalled(in: existing) { return .alreadyInstalled(file) }

        let separator = existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n"
        let updated = existing + separator + block(for: shell) + "\n"
        do {
            try Data(updated.utf8).write(to: file)
            return .installed(file)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
