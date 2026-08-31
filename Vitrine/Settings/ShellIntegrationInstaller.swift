import AppKit
import Darwin
import Foundation

/// Adds the `vgrab` shell helper to the user's shell startup file
/// (the one-click counterpart of pasting `eval "$(vitrine shell-init zsh)"` by
/// hand), surfaced as a Settings ▸ General row beside the CLI installer.
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
    /// Shell startup files should stay small, human-editable configuration. Refuse an
    /// unexpectedly large selection before allocating a second copy or appending to a
    /// path that may not be the file the user intended to grant.
    static let maxStartupFileBytes = 1 * 1_024 * 1_024

    /// The line a startup file evaluates to load the helper. zsh/bash use
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
        "# Vitrine shell integration (vgrab)\n\(evalLine(for: shell))"
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
    /// not now. fish's config lives under `~/.config/fish/`, which `>>` will not
    /// create — so the fish command makes that directory first.
    static func terminalCommand(for shell: ShellInit.Shell) -> String {
        let line = "echo '\(evalLine(for: shell))'"
        switch shell {
        case .zsh: return "\(line) >> ~/.zshrc"
        case .bash: return "\(line) >> ~/.bashrc"
        case .fish: return "mkdir -p ~/.config/fish && \(line) >> ~/.config/fish/config.fish"
        }
    }

    /// The result of an install attempt into a powerbox-granted file.
    enum InstallOutcome: Equatable {
        case installed(URL)
        /// The file already activates the integration — a no-op, surfaced so the
        /// UI can say so rather than silently appearing to do nothing.
        case alreadyInstalled(URL)
        case failed(String)
    }

    /// Appends the integration block to `file` (a startup file the user just granted
    /// through the open panel), idempotently and without rebuilding the entire file.
    ///
    /// One descriptor is opened for the complete read/check/append transaction. A
    /// non-blocking advisory lock avoids waiting on another cooperative editor, `fstat`
    /// rejects directories/devices and detects size or identity changes, and the read
    /// retains at most `maxStartupFileBytes + 1` bytes. `O_APPEND` prevents stale offsets
    /// from overwriting existing bytes. Atomic replacement is deliberately not used:
    /// the powerbox grant covers the selected file, not a temporary sibling in its
    /// parent directory.
    static func install(_ shell: ShellInit.Shell, into file: URL) -> InstallOutcome {
        let didScope = file.startAccessingSecurityScopedResource()
        defer { if didScope { file.stopAccessingSecurityScopedResource() } }

        guard let descriptor = openDescriptor(at: file) else { return .failed(readFailureMessage) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            return .failed(readFailureMessage)
        }
        defer { _ = Darwin.lockf(descriptor, F_ULOCK, 0) }

        do {
            let initialStatus = try regularFileStatus(for: descriptor)
            let initialByteCount = try boundedByteCount(initialStatus)
            try handle.seek(toOffset: 0)
            let existingData = try readBounded(from: handle)
            let finalStatus = try regularFileStatus(for: descriptor)
            guard
                initialStatus.st_dev == finalStatus.st_dev,
                initialStatus.st_ino == finalStatus.st_ino,
                finalStatus.st_size == initialStatus.st_size,
                existingData.count == initialByteCount
            else {
                return .failed(readFailureMessage)
            }
            guard let existing = String(data: existingData, encoding: .utf8) else {
                return .failed(readFailureMessage)
            }
            if isInstalled(in: existing) { return .alreadyInstalled(file) }

            let separator = existingData.isEmpty || existingData.last == 0x0A ? "" : "\n"
            let suffix = Data((separator + block(for: shell) + "\n").utf8)
            guard try handle.seekToEnd() == UInt64(initialByteCount) else {
                return .failed(readFailureMessage)
            }
            try handle.write(contentsOf: suffix)
            try handle.synchronize()
            let writtenStatus = try regularFileStatus(for: descriptor)
            guard writtenStatus.st_size == initialStatus.st_size + off_t(suffix.count) else {
                throw InstallError.writeFailed
            }
            return .installed(file)
        } catch InstallError.tooLarge {
            return .failed(
                String(
                    localized:
                        "The startup file is too large to update safely. Add the line by hand instead."
                ))
        } catch {
            return .failed(readFailureMessage)
        }
    }

    private enum InstallError: Error {
        case unreadable
        case notRegularFile
        case tooLarge
        case writeFailed
    }

    private static var readFailureMessage: String {
        String(
            localized:
                "Couldn't read the startup file (is it valid UTF-8?). Add the line by hand instead."
        )
    }

    private static func openDescriptor(at file: URL) -> Int32? {
        let descriptor = file.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(
                path, O_RDWR | O_APPEND | O_CREAT | O_CLOEXEC | O_NONBLOCK,
                S_IRUSR | S_IWUSR)
        }
        return descriptor >= 0 ? descriptor : nil
    }

    private static func regularFileStatus(for descriptor: Int32) throws -> stat {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { throw InstallError.unreadable }
        guard status.st_mode & S_IFMT == S_IFREG else { throw InstallError.notRegularFile }
        return status
    }

    private static func boundedByteCount(_ status: stat) throws -> Int {
        guard let count = Int(exactly: status.st_size), count >= 0 else {
            throw InstallError.unreadable
        }
        guard count <= maxStartupFileBytes else { throw InstallError.tooLarge }
        return count
    }

    private static func readBounded(from handle: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(min(maxStartupFileBytes, 64 * 1_024))
        while data.count <= maxStartupFileBytes {
            let remaining = maxStartupFileBytes + 1 - data.count
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)), !chunk.isEmpty
            else { break }
            data.append(chunk)
        }
        guard data.count <= maxStartupFileBytes else { throw InstallError.tooLarge }
        return data
    }
}
