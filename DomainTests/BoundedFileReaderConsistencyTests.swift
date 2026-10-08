import Darwin
import Foundation
import Testing

@testable import VitrineDomain

@Suite("Bounded file read consistency")
struct BoundedFileReaderConsistencyTests {
    @Test func rejectsASameLengthRewriteBetweenChunks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "VitrineReaderConsistency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("input.txt")
        let original = Data(repeating: 65, count: 128 * 1024)
        let replacement = Data(repeating: 66, count: original.count)
        try original.write(to: url)
        let oldDate = try #require(
            FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        var didRewrite = false
        var rewriteError: (any Error)?

        #expect(throws: BoundedFileReader.ReadError.unreadable) {
            _ = try BoundedFileReader.read(from: url, limit: original.count) { _ in
                guard !didRewrite else { return }
                didRewrite = true
                // The reader maps hook errors to `unreadable`; record them so a failed
                // rewrite cannot satisfy the expectation above.
                do {
                    let writer = try FileHandle(forWritingTo: url)
                    defer { try? writer.close() }
                    try writer.write(contentsOf: replacement)
                    // Pin distinct metadata without relying on scheduler delays or clock resolution.
                    try FileManager.default.setAttributes(
                        [.modificationDate: oldDate.addingTimeInterval(10)], ofItemAtPath: url.path)
                } catch {
                    rewriteError = error
                }
            }
        }
        #expect(didRewrite)
        #expect(rewriteError == nil)
        #expect(try Data(contentsOf: url) == replacement)
    }

    @Test func rejectsChangeTimeEvenWhenModificationTimeIsRestored() throws {
        var initial = stat()
        initial.st_mtimespec = timespec(tv_sec: 100, tv_nsec: 20)
        initial.st_ctimespec = timespec(tv_sec: 100, tv_nsec: 30)
        var final = initial
        final.st_ctimespec.tv_nsec += 1

        #expect(throws: BoundedFileReader.ReadError.unreadable) {
            try BoundedFileReader.validateChangeEvidence(initial: initial, final: final)
        }
    }

    @Test func acceptsUnchangedEvidence() throws {
        var status = stat()
        status.st_mtimespec = timespec(tv_sec: 100, tv_nsec: 20)
        status.st_ctimespec = timespec(tv_sec: 100, tv_nsec: 30)
        try BoundedFileReader.validateChangeEvidence(initial: status, final: status)
    }
}
