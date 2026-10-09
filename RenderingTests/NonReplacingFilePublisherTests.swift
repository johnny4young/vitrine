import Foundation
import Testing

@testable import VitrineRendering

@Suite("Shared publication failure ownership")
struct NonReplacingFilePublisherTests {
    enum Failure: Error, Equatable { case write }

    @Test func fallbackFailureDoesNotDeleteAReplacementOwnedByAnotherProducer() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("publication-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output.png")
        let winner = Data("replacement owned by another producer".utf8)

        #expect(throws: Failure.write) {
            try NonReplacingFilePublisher.publishByExclusiveCreate(Data("new".utf8), to: output) {
                handle, bytes in
                try handle.write(contentsOf: bytes.prefix(1))
                try FileManager.default.removeItem(at: output)
                try winner.write(to: output)
                throw Failure.write
            }
        }

        #expect(try Data(contentsOf: output) == winner)
    }
}
