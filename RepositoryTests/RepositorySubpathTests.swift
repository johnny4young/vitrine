import Foundation
import Testing

@Suite("Repository subpaths")
struct RepositorySubpathTests {
    @Test func aRootReachedThroughASymlinkMatchesResolvedFiles() throws {
        try Self.withSandbox { real, link, _ in
            let file = real.appending(path: "Vitrine/Settings/File.swift")
            #expect(file.subpath(under: link) == "Vitrine/Settings/File.swift")
            #expect(file.subpath(under: real) == "Vitrine/Settings/File.swift")
        }
    }

    @Test func aSymlinkedFileCountsWhereItIsListed() throws {
        try Self.withSandbox { real, link, outside in
            let listed = real.appending(path: "docs/shared.md")
            try FileManager.default.createSymbolicLink(at: listed, withDestinationURL: outside)
            #expect(listed.subpath(under: link) == "docs/shared.md")
        }
    }

    @Test func filesOutsideTheRootHaveNoSubpath() throws {
        try Self.withSandbox { real, link, outside in
            #expect(outside.subpath(under: link) == nil)
            #expect(real.subpath(under: link) == nil)
        }
    }

    /// A checkout at `real`, a symlink `link` to it, and a file beside the checkout.
    private static func withSandbox(_ body: (URL, URL, URL) throws -> Void) throws {
        let fileManager = FileManager.default
        let sandbox = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fileManager.removeItem(at: sandbox) }
        let real = sandbox.appending(path: "checkout")
        let link = sandbox.appending(path: "link")
        let outside = sandbox.appending(path: "outside.md")
        for directory in ["Vitrine/Settings", "docs"] {
            try fileManager.createDirectory(
                at: real.appending(path: directory), withIntermediateDirectories: true)
        }
        try Data().write(to: real.appending(path: "Vitrine/Settings/File.swift"))
        try Data().write(to: outside)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        try body(real, link, outside)
    }
}
