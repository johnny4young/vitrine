import AppKit
import Darwin
import Foundation

/// Installs the embedded `vitrine` command-line tool onto the user's PATH
/// the DMG-install counterpart of the Homebrew cask's `binary`
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
    enum HostArchitecture: String, Equatable {
        case arm64
        case x8664 = "x86_64"
        case other

        init(machine: String) {
            switch machine.lowercased() {
            case "arm64", "aarch64": self = .arm64
            case "x86_64", "amd64": self = .x8664
            default: self = .other
            }
        }
    }

    /// The CLI embedded in the running app bundle
    /// (`Contents/MacOS/vitrine-cli`), or `nil` when this copy of the app does
    /// not carry it (the Settings row hides itself then).
    static var embeddedCLI: URL? {
        let url =
            Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/vitrine-cli")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// PATH directories probed for an existing `vitrine` link. Native Homebrew is
    /// preferred for the running architecture, with the other prefix retained as a
    /// compatibility fallback for mixed Intel/Apple-Silicon setups.
    static var knownBinDirectories: [URL] {
        binDirectories(for: currentArchitecture)
    }

    static func binDirectories(for architecture: HostArchitecture) -> [URL] {
        let appleSilicon = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
        let traditional = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        switch architecture {
        case .arm64: return [appleSilicon, traditional]
        case .x8664, .other: return [traditional, appleSilicon]
        }
    }

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
            let destinationURL = resolvedDestination(destination, relativeTo: link)
            if canonicalURL(destinationURL) == canonicalURL(target) { return link }
        }
        return nil
    }

    /// The Terminal equivalent of the install, shown (and copyable) when the chosen
    /// folder refuses the write. It intentionally omits `-f`: a fallback command must
    /// never unlink a regular file that happens to be named `vitrine`.
    ///
    /// The command targets the first of the architecture's conventional prefixes
    /// that actually exists — on an Apple-silicon Mac without Homebrew,
    /// `/opt/homebrew/bin` is missing and `ln` could not create it, so the
    /// traditional prefix is the one that works. When neither exists, the command
    /// creates the traditional prefix first. Pass `directory` to point the command
    /// at the exact folder a failed in-app install just attempted, so the copied
    /// command is truly the equivalent action.
    static func terminalCommand(
        for target: URL,
        into directory: URL? = nil,
        architecture: HostArchitecture? = nil,
        directoryExists: (URL) -> Bool = { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    ) -> String {
        let link = "sudo ln -s \(ShellCommandQuoter.singleQuoted(canonicalURL(target).path)) "
        if let directory {
            return link + directory.appendingPathComponent("vitrine").path
        }
        let resolvedArchitecture = architecture ?? currentArchitecture
        let candidates = binDirectories(for: resolvedArchitecture)
        if let existing = candidates.first(where: directoryExists) {
            return link + existing.appendingPathComponent("vitrine").path
        }
        let traditional = candidates.first { $0.path == "/usr/local/bin" } ?? candidates[0]
        return "sudo mkdir -p \(traditional.path) && "
            + link + traditional.appendingPathComponent("vitrine").path
    }

    /// The result of an install attempt into a powerbox-granted folder.
    enum InstallOutcome: Equatable {
        case installed(URL)
        case failed(String)
    }

    /// Links the canonical `target` as `vitrine` inside `directory` (a folder the user
    /// just granted through the open panel). The candidate link is created under a
    /// unique sibling name and then installed with one kernel rename operation. A
    /// stale symlink is swapped atomically; a real file or a concurrently-created
    /// destination is never deleted.
    static func install(
        _ target: URL, into directory: URL, fileManager: FileManager = .default
    ) -> InstallOutcome {
        let didScope = directory.startAccessingSecurityScopedResource()
        defer { if didScope { directory.stopAccessingSecurityScopedResource() } }

        let link = directory.appendingPathComponent("vitrine")
        let temporaryLink = directory.appendingPathComponent(
            ".vitrine-link-\(UUID().uuidString)")
        let destinationState: DestinationState
        do {
            destinationState = try state(of: link)
        } catch {
            return .failed(installFailureMessage)
        }

        guard destinationState != .nonSymlink else {
            return .failed(
                String(
                    localized:
                        "A regular item named vitrine already exists in the selected folder. Move it before installing the command."
                )
            )
        }

        do {
            try fileManager.createSymbolicLink(
                at: temporaryLink, withDestinationURL: canonicalURL(target))
            defer {
                // Never let cleanup remove a regular file if an uncooperative writer
                // races the atomic swap. A leftover unexpected item is safer than data
                // loss and makes the failed state inspectable.
                if (try? state(of: temporaryLink)) == .symlink {
                    try? fileManager.removeItem(at: temporaryLink)
                }
            }

            switch destinationState {
            case .missing:
                guard rename(temporaryLink, to: link, flags: UInt32(RENAME_EXCL)) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            case .symlink:
                guard rename(temporaryLink, to: link, flags: UInt32(RENAME_SWAP)) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                // The old link is now at `temporaryLink` and is removed by the defer.
                // Re-check without following it: if an uncooperative writer raced the
                // preflight, swap back rather than discard a regular file.
                guard try state(of: temporaryLink) == .symlink else {
                    _ = rename(temporaryLink, to: link, flags: UInt32(RENAME_SWAP))
                    throw POSIXError(.EEXIST)
                }
            case .nonSymlink:
                throw POSIXError(.EEXIST)
            }
            return .installed(link)
        } catch {
            return .failed(installFailureMessage)
        }
    }

    private enum DestinationState: Equatable {
        case missing
        case symlink
        case nonSymlink
    }

    private static var installFailureMessage: String {
        String(localized: "Couldn't safely update the command link in the selected folder.")
    }

    private static var currentArchitecture: HostArchitecture {
        var value = utsname()
        guard Darwin.uname(&value) == 0 else { return .other }
        let machine = withUnsafeBytes(of: &value.machine) { rawBuffer -> String in
            let bytes = rawBuffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return HostArchitecture(machine: machine)
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func resolvedDestination(_ destination: String, relativeTo link: URL) -> URL {
        if destination.hasPrefix("/") { return URL(fileURLWithPath: destination) }
        return link.deletingLastPathComponent().appendingPathComponent(destination)
    }

    private static func state(of url: URL) throws -> DestinationState {
        var status = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &status)
        }
        if result == 0 {
            return status.st_mode & S_IFMT == S_IFLNK ? .symlink : .nonSymlink
        }
        if errno == ENOENT { return .missing }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func rename(_ source: URL, to destination: URL, flags: UInt32) -> Int32 {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return Darwin.renameatx_np(
                    AT_FDCWD, sourcePath, AT_FDCWD, destinationPath, flags)
            }
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
