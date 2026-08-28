import Foundation
import Testing

@testable import Vitrine

@Suite("BoundedFileReader")
struct BoundedFileReaderTests {
    @Test func readsARegularFileAtTheExactLimit() throws {
        let bytes = Data("hello".utf8)
        let (directory, url) = try temporaryFile(data: bytes)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try BoundedFileReader.read(from: url, limit: bytes.count) == bytes)
    }

    @Test func rejectsARegularFileAboveTheLimit() throws {
        let (directory, url) = try temporaryFile(data: Data("123456".utf8))
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: BoundedFileReader.ReadError.tooLarge) {
            _ = try BoundedFileReader.read(from: url, limit: 5)
        }
    }

    @Test func rejectsDirectoriesAndMissingFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineBoundedReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: BoundedFileReader.ReadError.notRegularFile) {
            _ = try BoundedFileReader.read(from: directory, limit: 10)
        }
        #expect(throws: BoundedFileReader.ReadError.unreadable) {
            _ = try BoundedFileReader.read(
                from: directory.appendingPathComponent("missing"), limit: 10)
        }
    }

    @Test func classifiesGrowingAndShrinkingFilesDeterministically() {
        #expect(throws: BoundedFileReader.ReadError.tooLarge) {
            try BoundedFileReader.validateStableRead(
                initialByteCount: 5, finalByteCount: 6, readByteCount: 6)
        }
        #expect(throws: BoundedFileReader.ReadError.unreadable) {
            try BoundedFileReader.validateStableRead(
                initialByteCount: 5, finalByteCount: 4, readByteCount: 4)
        }
    }

    private func temporaryFile(data: Data) throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineBoundedReader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("input")
        try data.write(to: file)
        return (directory, file)
    }
}
