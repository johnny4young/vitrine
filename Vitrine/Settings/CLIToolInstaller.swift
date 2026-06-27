import AppKit
import Foundation

/// Installs the embedded `vitrine` command-line tool onto the user's PATH
/// (CS-033) — the DMG-install counterpart of the Homebrew cask's `binary`
/// stanza, surfaced as a Settings ▸ General row.
///
/// The app is sandboxed, so it cannot write into PATH directories on its own:
/// the user picks the destination folder through the open panel (the powerbox
/// grants write access to exactly that folder), and the symlink is created
/// inside the grant. A system-owned folder such as `/usr/local/bin` still
/// refuses the write at the POSIX layer (it is root-owned), in which case the
/// UI falls back to a copyable Terminal command — the honest, sandbox-true
/// behavior rather than a privilege prompt the sandbox forbids.
enum CLIToolInstaller {
    /// The CLI embedded in the running app bundle
    /// (`Contents/MacOS/vitrine-cli`), or `nil` when this copy of the app does
    /// not carry it (the Settings row hides itself then).
    static var embeddedCLI: URL? {
        let url =
            Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/vitrine-cli")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// PATH directories probed for an existing `vitrine` link, in order: the
    /// Apple Silicon Homebrew prefix (user-writable on brew installs), then the
    /// traditional `/usr/local/bin`.
    static let knownBinDirectories = [
        URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
        URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
    ]

    /// Where `vitrine` is already linked to `target`, or `nil` when no probed
    /// directory carries a matching link. Parameterized so tests can point it
    /// at temporary directories; a sandbox-denied read simply reports "not
    /// installed", which the install flow tolerates (re-linking is idempotent).
    static func installedLocation(
        of target: URL,
        searching directories: [URL] = knownBinDirectories,
        fileManager: FileManager = .default
    ) -> URL? {
        for directory in directories {
            let link = directory.appendingPathComponent("vitrine")
            guard
                let destination = try? fileManager.destinationOfSymbolicLink(
                    atPath: link.path)
            else { continue }
            if destination == target.path { return link }
        }
        return nil
    }

    /// The Terminal equivalent of the install, shown (and copyable) when the
    /// chosen folder refuses the write. `sudo` because `/usr/local/bin` is
    /// root-owned on a stock macOS.
    static func terminalCommand(for target: URL) -> String {
        "sudo ln -sf \(ShellCommandQuoter.singleQuoted(target.path)) /usr/local/bin/vitrine"
    }

    /// The result of an install attempt into a powerbox-granted folder.
    enum InstallOutcome: Equatable {
        case installed(URL)
        case failed(String)
    }

    /// Links `target` as `vitrine` inside `directory` (a folder the user just
    /// granted through the open panel). An existing entry is replaced only when
    /// it is itself a symlink — a real file named `vitrine` is never deleted.
    static func install(
        _ target: URL, into directory: URL, fileManager: FileManager = .default
    ) -> InstallOutcome {
        let didScope = directory.startAccessingSecurityScopedResource()
        defer { if didScope { directory.stopAccessingSecurityScopedResource() } }

        let link = directory.appendingPathComponent("vitrine")
        do {
            if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try fileManager.removeItem(at: link)
            }
            try fileManager.createSymbolicLink(at: link, withDestinationURL: target)
            return .installed(link)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Minimal POSIX-shell quoting for copyable fallback commands. A user can install
/// Vitrine in a folder whose path contains quotes, spaces, dollar signs, or command
/// substitutions; the fallback must treat that path as data when pasted into Terminal.
private enum ShellCommandQuoter {
    static func singleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
