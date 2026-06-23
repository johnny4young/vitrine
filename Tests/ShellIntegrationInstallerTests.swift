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
    }

    @Test func startupFileMapsTheShellToItsRCFile() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(
            ShellIntegrationInstaller.startupFile(for: .zsh, home: home).path
                == "/Users/test/.zshrc")
        #expect(
            ShellIntegrationInstaller.startupFile(for: .bash, home: home).path
                == "/Users/test/.bashrc")
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

    @Test func terminalCommandAppendsTheEvalLineToTheRCFile() {
        #expect(
            ShellIntegrationInstaller.terminalCommand(for: .zsh)
                == "echo 'eval \"$(vitrine shell-init zsh)\"' >> ~/.zshrc")
        #expect(
            ShellIntegrationInstaller.terminalCommand(for: .bash)
                == "echo 'eval \"$(vitrine shell-init bash)\"' >> ~/.bashrc")
    }
}
