import Foundation
import Testing

@testable import Vitrine

/// The Settings ▸ General "Command-line tool" install logic: linking
/// the embedded CLI onto PATH, detecting an existing link, and the Terminal
/// fallback for system-owned folders.
@Suite("CLI tool installer")
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
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: bin.path).sorted() == ["vitrine"],
            "the atomic staging symlink must be removed after installation")
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

    @Test func installedLocationCanonicalizesRelativeAndAliasSymlinks() throws {
        let root = try makeBinDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let payload = root.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: false)
        let target = payload.appendingPathComponent("vitrine-cli")
        try Data("cli".utf8).write(to: target)
        let alias = root.appendingPathComponent("cli-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(
            atPath: bin.appendingPathComponent("vitrine").path,
            withDestinationPath: "../payload/vitrine-cli")

        #expect(CLIToolInstaller.installedLocation(of: alias, searching: [bin]) != nil)
    }

    @Test func installLinksToTheCanonicalTargetAndReplacesAtomically() throws {
        let root = try makeBinDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("real-cli")
        try Data("cli".utf8).write(to: target)
        let alias = root.appendingPathComponent("cli-alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: false)
        let link = bin.appendingPathComponent("vitrine")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/old/vitrine-cli"))

        #expect(CLIToolInstaller.install(alias, into: bin) == .installed(link))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path) == ["vitrine"])
    }

    @Test func binDirectoryOrderFollowsTheHostArchitecture() {
        #expect(
            CLIToolInstaller.binDirectories(for: .arm64).map(\.path)
                == ["/opt/homebrew/bin", "/usr/local/bin"])
        #expect(
            CLIToolInstaller.binDirectories(for: .x8664).map(\.path)
                == ["/usr/local/bin", "/opt/homebrew/bin"])
        #expect(
            CLIToolInstaller.binDirectories(for: .other).map(\.path)
                == ["/usr/local/bin", "/opt/homebrew/bin"])
        #expect(CLIToolInstaller.HostArchitecture(machine: "aarch64") == .arm64)
        #expect(CLIToolInstaller.HostArchitecture(machine: "amd64") == .x8664)
        #expect(CLIToolInstaller.HostArchitecture(machine: "future") == .other)
    }

    /// The fallback command must target the conventional PATH location and ask
    /// for the privileges that root-owned folder actually requires.
    @Test func terminalCommandLinksIntoUsrLocalBinWithSudo() {
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")
        let command = CLIToolInstaller.terminalCommand(for: target, architecture: .x8664)
        #expect(
            command
                == "sudo ln -s '/Applications/Vitrine.app/Contents/MacOS/vitrine-cli' /usr/local/bin/vitrine"
        )
    }

    @Test func terminalCommandUsesTheNativeAppleSiliconPrefix() {
        let target = URL(fileURLWithPath: "/Applications/Vitrine.app/Contents/MacOS/vitrine-cli")
        #expect(
            CLIToolInstaller.terminalCommand(for: target, architecture: .arm64)
                == "sudo ln -s '/Applications/Vitrine.app/Contents/MacOS/vitrine-cli' /opt/homebrew/bin/vitrine"
        )
    }

    @Test func terminalCommandShellQuotesTheEmbeddedCLIPath() {
        let target = URL(
            fileURLWithPath:
                "/Applications/O'Malley $(touch pwned)/Vitrine.app/Contents/MacOS/vitrine-cli")
        let command = CLIToolInstaller.terminalCommand(for: target, architecture: .x8664)
        #expect(command.hasPrefix("sudo ln -s '"))
        #expect(command.contains(#"O'"'"'Malley $(touch pwned)"#))
        #expect(command.hasSuffix("/usr/local/bin/vitrine"))
    }
}
