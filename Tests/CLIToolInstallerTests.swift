import Foundation
import Testing

@testable import Vitrine

/// The Settings ▸ General "Command-line tool" install logic (CS-033): linking
/// the embedded CLI onto PATH, detecting an existing link, and the Terminal
/// fallback for system-owned folders.
@Suite("CLI tool installer (CS-033)")
struct CLIToolInstallerTests {
    /// A scratch directory standing in for a PATH bin folder.
    private func makeBinDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-cli-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func installCreatesASymlinkNamedVitrine() throws {
        let bin = try makeBinDirectory()
        defer { try? FileManager.default.removeItem(at: bin) }
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")

        let outcome = CLIToolInstaller.install(target, into: bin)

        let link = bin.appendingPathComponent("vitrine")
        #expect(outcome == .installed(link))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    @Test func installReplacesAStaleSymlink() throws {
        let bin = try makeBinDirectory()
        defer { try? FileManager.default.removeItem(at: bin) }
        let link = bin.appendingPathComponent("vitrine")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/old/location/vitrine-cli"))
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")

        let outcome = CLIToolInstaller.install(target, into: bin)

        #expect(outcome == .installed(link))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    }

    /// A real file named `vitrine` is never deleted — the install fails instead
    /// of destroying something the user (or another tool) put there.
    @Test func installNeverDeletesARegularFile() throws {
        let bin = try makeBinDirectory()
        defer { try? FileManager.default.removeItem(at: bin) }
        let existing = bin.appendingPathComponent("vitrine")
        try Data("not a symlink".utf8).write(to: existing)
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")

        let outcome = CLIToolInstaller.install(target, into: bin)

        guard case .failed = outcome else {
            Issue.record("expected the install to refuse to replace a regular file")
            return
        }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "not a symlink")
    }

    @Test func installedLocationFindsAMatchingLinkAndIgnoresOthers() throws {
        let matching = try makeBinDirectory()
        let unrelated = try makeBinDirectory()
        defer {
            try? FileManager.default.removeItem(at: matching)
            try? FileManager.default.removeItem(at: unrelated)
        }
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")
        try FileManager.default.createSymbolicLink(
            at: unrelated.appendingPathComponent("vitrine"),
            withDestinationURL: URL(fileURLWithPath: "/somewhere/else"))
        try FileManager.default.createSymbolicLink(
            at: matching.appendingPathComponent("vitrine"), withDestinationURL: target)

        #expect(
            CLIToolInstaller.installedLocation(of: target, searching: [unrelated, matching])
                == matching.appendingPathComponent("vitrine"))
        #expect(CLIToolInstaller.installedLocation(of: target, searching: [unrelated]) == nil)
    }

    /// The fallback command must target the conventional PATH location and ask
    /// for the privileges that root-owned folder actually requires.
    @Test func terminalCommandLinksIntoUsrLocalBinWithSudo() {
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")
        let command = CLIToolInstaller.terminalCommand(for: target)
        #expect(
            command
                == "sudo ln -sf '/Applications/Vitrine.app/Contents/MacOS/vitrine-cli' /usr/local/bin/vitrine"
        )
    }

    @Test func terminalCommandShellQuotesTheEmbeddedCLIPath() {
        let target = URL(
            fileURLWithPath:
                "/Applications/O'Malley $(touch pwned)/Vitrine.app/Contents/MacOS/vitrine-cli")
        let command = CLIToolInstaller.terminalCommand(for: target)
        #expect(command.hasPrefix("sudo ln -sf '"))
        #expect(command.contains(#"O'"'"'Malley $(touch pwned)"#))
        #expect(command.hasSuffix("/usr/local/bin/vitrine"))
    }
}
