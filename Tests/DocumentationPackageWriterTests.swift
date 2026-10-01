import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Transactional documentation writing")
struct DocumentationPackageWriterTests {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    @Test func commitsAllFilesAndLeavesNoStaging() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let package = DocumentationPackage(
            config: SnapshotConfig(code: "safe", language: .swift), png: Data([7]),
            representations: [.markdown, .html, .text])
        let final = try await DocumentationPackageWriter.write(
            package, parent: parent, name: "docs")
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["docs"])
        for (name, data) in package.files {
            #expect(try Data(contentsOf: final.appendingPathComponent(name)) == data)
        }
    }

    @Test(arguments: [
        "", ".", "..", "../escape", "nested/file", "nested\\file", "bad\0name",
        String(repeating: "x", count: 256),
    ])
    func rejectsUnsafeNames(_ name: String) async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data(), representations: [])
        await #expect(throws: DocumentationPackageWriter.WriteError.invalidName) {
            try await DocumentationPackageWriter.write(package, parent: parent, name: name)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    @Test func validatesParentAndResolvesAnExplicitParentSymlink() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("parent")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let link = root.appendingPathComponent("selected-parent")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: parent)
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data([7]), representations: [])
        let final = try await DocumentationPackageWriter.write(package, parent: link, name: "docs")
        #expect(
            final
                == parent.resolvingSymlinksInPath().appendingPathComponent(
                    "docs", isDirectory: true))
        let file = root.appendingPathComponent("not-a-directory")
        try Data([9]).write(to: file)
        await #expect(throws: DocumentationPackageWriter.WriteError.invalidParent) {
            try await DocumentationPackageWriter.write(package, parent: file, name: "docs")
        }
        await #expect(throws: DocumentationPackageWriter.WriteError.invalidParent) {
            try await DocumentationPackageWriter.write(
                package, parent: URL(string: "https://example.invalid")!, name: "docs")
        }
        #expect(try Data(contentsOf: file) == Data([9]))
    }

    @Test func unwritableParentFailsWithoutPublishingAnything() async throws {
        let parent = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data([7]), representations: [])
        await #expect(throws: CocoaError.self) {
            try await DocumentationPackageWriter.write(package, parent: parent, name: "docs")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }

    @Test func concurrentCommitsProduceExactlyOneCompleteWinner() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let package = DocumentationPackage(
            config: SnapshotConfig(code: "safe", language: .swift), png: Data([7]),
            representations: [.markdown, .html, .text])
        let wins = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do {
                        _ = try await DocumentationPackageWriter.write(
                            package, parent: parent, name: "docs")
                        return true
                    } catch DocumentationPackageWriter.WriteError.destinationExists {
                        return false
                    } catch {
                        Issue.record("Unexpected transaction error: \(error)")
                        return false
                    }
                }
            }
            var count = 0
            for await won in group { if won { count += 1 } }
            return count
        }
        #expect(wins == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["docs"])
        for (name, data) in package.files {
            #expect(
                try Data(
                    contentsOf: parent.appendingPathComponent("docs").appendingPathComponent(name))
                    == data)
        }
    }

    @Test func failureCleansOnlyOwnedStagingAndPreservesOtherFiles() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let sentinel = parent.appendingPathComponent("existing.txt")
        try Data([9]).write(to: sentinel)
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data(), representations: [.markdown])
        await #expect(throws: CocoaError.self) {
            try await DocumentationPackageWriter.write(
                package, parent: parent, name: "docs",
                writeFile: { data, url in
                    if url.lastPathComponent == "image.png" {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    try data.write(to: url)
                })
        }
        #expect(try Data(contentsOf: sentinel) == Data([9]))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["existing.txt"])
    }

    @Test func commitTimeCollisionNeverReplacesEvenAnEmptyDirectory() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("docs")
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data([5]), representations: [])
        await #expect(throws: DocumentationPackageWriter.WriteError.destinationExists) {
            try await DocumentationPackageWriter.write(
                package, parent: parent, name: "docs",
                writeFile: { data, url in
                    try data.write(to: url)
                    try FileManager.default.createDirectory(
                        at: destination, withIntermediateDirectories: false)
                })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path) == ["docs"])
    }

    @Test func danglingOutputSymlinkIsNeverFollowedOrDeleted() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let destination = parent.appendingPathComponent("docs")
        try FileManager.default.createSymbolicLink(
            at: destination, withDestinationURL: parent.appendingPathComponent("absent"))
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data(), representations: [])
        await #expect(throws: DocumentationPackageWriter.WriteError.destinationExists) {
            try await DocumentationPackageWriter.write(package, parent: parent, name: "docs")
        }
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.path).contains(
                "absent"))
    }

    @Test func cancellationBetweenWritesLeavesNoPackage() async throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let package = DocumentationPackage(
            config: SnapshotConfig(), png: Data(), representations: [.markdown])
        let task = Task {
            try await DocumentationPackageWriter.write(
                package, parent: parent, name: "docs",
                writeFile: { data, url in
                    try data.write(to: url)
                    withUnsafeCurrentTask { $0?.cancel() }
                })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: parent.path).isEmpty)
    }
}
