import Foundation
import Testing

@testable import Vitrine

/// The Settings ▸ General "Shell integration" one-click install logic: appending
/// the `eval "$(vitrine shell-init …)"` line to a startup file, idempotently,
/// plus the eval-line / startup-path / Terminal-fallback helpers.
@Suite("Shell integration installer")
struct ShellIntegrationInstallerTests {
    /// A scratch file standing in for the user's `~/.zshrc`.
    private func makeStartupFile(_ contents: String? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-rc-\(UUID().uuidString)")
        if let contents { try contents.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    @Test func evalLineNamesTheRequestedShell() {
        #expect(
            ShellIntegrationInstaller.evalLine(for: .zsh) == "eval \"$(vitrine shell-init zsh)\"")
        #expect(
            ShellIntegrationInstaller.evalLine(for: .bash) == "eval \"$(vitrine shell-init bash)\"")
        // fish has no `$(…)`: it sources a pipe instead.
        #expect(
            ShellIntegrationInstaller.evalLine(for: .fish) == "vitrine shell-init fish | source")
    }

    @Test func startupFileMapsTheShellToItsRCFile() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(
            ShellIntegrationInstaller.startupFile(for: .zsh, home: home).path
                == "/Users/test/.zshrc")
        #expect(
            ShellIntegrationInstaller.startupFile(for: .bash, home: home).path
                == "/Users/test/.bashrc")
        #expect(
            ShellIntegrationInstaller.startupFile(for: .fish, home: home).path
                == "/Users/test/.config/fish/config.fish")
    }

    @Test func installAppendsTheBlockToAnExistingFile() throws {
        let file = try makeStartupFile("export PATH=/usr/bin\n")
        defer { try? FileManager.default.removeItem(at: file) }

        let outcome = ShellIntegrationInstaller.install(.zsh, into: file)

        #expect(outcome == .installed(file))
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.hasPrefix("export PATH=/usr/bin\n"))
        #expect(written.contains("eval \"$(vitrine shell-init zsh)\""))
        #expect(written.contains("# Vitrine shell integration"))
        #expect(written.hasSuffix("\n"))
    }

    @Test func installInsertsASeparatingNewlineWhenTheFileLacksATrailingOne() throws {
        // No trailing newline: the eval line must not glue onto the last line.
        let file = try makeStartupFile("alias ll='ls -la'")
        defer { try? FileManager.default.removeItem(at: file) }

        _ = ShellIntegrationInstaller.install(.zsh, into: file)

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("alias ll='ls -la'\n# Vitrine shell integration"))
    }

    @Test func installCreatesTheFileWhenItDoesNotExistYet() throws {
        let file = try makeStartupFile()  // not written → does not exist
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(!FileManager.default.fileExists(atPath: file.path))

        let outcome = ShellIntegrationInstaller.install(.zsh, into: file)

        #expect(outcome == .installed(file))
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written == ShellIntegrationInstaller.block(for: .zsh) + "\n")
    }

    @Test func installIsIdempotentWhenAlreadyPresent() throws {
        let file = try makeStartupFile("eval \"$(vitrine shell-init zsh)\"\n")
        defer { try? FileManager.default.removeItem(at: file) }

        let outcome = ShellIntegrationInstaller.install(.zsh, into: file)

        #expect(outcome == .alreadyInstalled(file))
        // Untouched: a single occurrence, no duplicate appended.
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.components(separatedBy: "vitrine shell-init").count - 1 == 1)
    }

    @Test func installDetectsAHandPastedLineRegardlessOfShell() throws {
        // A bash eval line already present blocks a re-append even for zsh: the
        // marker, not the exact line, is what we key on.
        let file = try makeStartupFile("eval \"$(vitrine shell-init bash)\"\n")
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(ShellIntegrationInstaller.install(.zsh, into: file) == .alreadyInstalled(file))
    }

    @Test func installRefusesToClobberAnUnreadableExistingFile() throws {
        // A file that exists but isn't valid UTF-8 must NOT be treated as empty and
        // overwritten with only our block — that would lose the user's content.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-rc-\(UUID().uuidString)")
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFF, 0x00, 0x80])
        try invalidUTF8.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let outcome = ShellIntegrationInstaller.install(.zsh, into: file)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        // The original bytes are untouched — nothing was clobbered.
        #expect(try Data(contentsOf: file) == invalidUTF8)
    }

    @Test func installRefusesAnOversizedStartupFileWithoutReadingOrChangingIt() throws {
        let file = try makeStartupFile()
        let original = Data(
            repeating: 0x61, count: ShellIntegrationInstaller.maxStartupFileBytes + 1)
        try original.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let outcome = ShellIntegrationInstaller.install(.zsh, into: file)

        guard case .failed(let message) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func installRejectsANonRegularSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-rc-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        guard case .failed = ShellIntegrationInstaller.install(.zsh, into: directory) else {
            Issue.record("expected a directory selection to fail closed")
            return
        }
        #expect(
            FileManager.default.fileExists(atPath: directory.path),
            "the selected directory must remain untouched")
    }

    @Test func installAppendsOnlyTheSmallIntegrationSuffix() throws {
        let original = String(repeating: "export VALUE=1\n", count: 4_096)
        let file = try makeStartupFile(original)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(ShellIntegrationInstaller.install(.bash, into: file) == .installed(file))

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.hasPrefix(original))
        #expect(
            written.dropFirst(original.count) == ShellIntegrationInstaller.block(for: .bash) + "\n")
    }

    @Test func terminalCommandAppendsTheEvalLineToTheRCFile() {
        #expect(
            ShellIntegrationInstaller.terminalCommand(for: .zsh)
                == "echo 'eval \"$(vitrine shell-init zsh)\"' >> ~/.zshrc")
        #expect(
            ShellIntegrationInstaller.terminalCommand(for: .bash)
                == "echo 'eval \"$(vitrine shell-init bash)\"' >> ~/.bashrc")
        // fish: `>>` can't create ~/.config/fish/, so the command makes it first.
        #expect(
            ShellIntegrationInstaller.terminalCommand(for: .fish)
                == "mkdir -p ~/.config/fish && echo 'vitrine shell-init fish | source' "
                + ">> ~/.config/fish/config.fish")
    }
}

extension ShellIntegrationInstallerTests {
    /// An editor that saves atomically renames a fresh file over the startup
    /// file's pathname. The descriptor then still points at the old, unlinked
    /// inode — the path check is what must notice.
    @Test func pathnameCheckDetectsAtomicReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rcFile = directory.appendingPathComponent(".zshrc")
        try Data("# original\n".utf8).write(to: rcFile)

        let descriptor = open(rcFile.path, O_RDWR)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        var status = stat()
        #expect(fstat(descriptor, &status) == 0)

        // Same inode: the pathname still resolves to the open descriptor.
        #expect(ShellIntegrationInstaller.pathnameResolves(rcFile, toDeviceAndInodeOf: status))

        // An atomic editor save: a new file renamed over the same pathname.
        let replacement = directory.appendingPathComponent(".zshrc.new")
        try Data("# replaced\n".utf8).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(rcFile, withItemAt: replacement)

        #expect(!ShellIntegrationInstaller.pathnameResolves(rcFile, toDeviceAndInodeOf: status))
    }

    /// A deleted pathname (no replacement at all) also fails the check.
    @Test func pathnameCheckFailsForADeletedPath() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-\(UUID().uuidString).zshrc")
        try Data("# original\n".utf8).write(to: file)
        let descriptor = open(file.path, O_RDWR)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        var status = stat()
        #expect(fstat(descriptor, &status) == 0)

        try FileManager.default.removeItem(at: file)
        #expect(!ShellIntegrationInstaller.pathnameResolves(file, toDeviceAndInodeOf: status))
    }
}
