import Foundation
import Testing

@testable import Vitrine

@Suite("Non-replacing GUI batch files")
struct BatchOutputFilesTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineBatchFiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func plansImagesAndSidecarsTogetherIncludingDuplicateNames() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = Data("existing source".utf8)
        let occupied = directory.appendingPathComponent("vitrine-twitter.txt")
        try original.write(to: occupied)

        let plan = try BatchOutputFiles.plan(
            filenames: ["vitrine-twitter.png", "vitrine-twitter.png"],
            in: directory, textSidecars: true)

        #expect(plan.map { $0.image.lastPathComponent } == [
            "vitrine-twitter-2.png", "vitrine-twitter-3.png",
        ])
        #expect(plan.map { $0.sidecar?.lastPathComponent } == [
            "vitrine-twitter-2.txt", "vitrine-twitter-3.txt",
        ])
        #expect(try Data(contentsOf: occupied) == original)
    }

    @Test func raceCreatedDestinationSurvivesAndStageIsCleaned() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try #require(
            BatchOutputFiles.plan(filenames: ["carousel-01.png"], in: directory).first)
        let original = Data("race winner".utf8)

        #expect(throws: (any Error).self) {
            try BatchOutputFiles.publish(Data("new image".utf8), to: output.image) {
                try original.write(to: output.image, options: .withoutOverwriting)
            }
        }

        #expect(try Data(contentsOf: output.image) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [
            "carousel-01.png"
        ])
    }

    @Test func sidecarFailureKeepsCompletedImageAndPreviousSidecar() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try #require(
            BatchOutputFiles.plan(
                filenames: ["image.png"], in: directory, textSidecars: true).first)
        let sidecar = try #require(output.sidecar)
        let image = Data("complete image".utf8)
        let original = Data("previous sidecar".utf8)
        try BatchOutputFiles.publish(image, to: output.image)
        try original.write(to: sidecar)

        #expect(throws: (any Error).self) {
            try BatchOutputFiles.publish(Data("new sidecar".utf8), to: sidecar)
        }
        #expect(try Data(contentsOf: output.image) == image)
        #expect(try Data(contentsOf: sidecar) == original)
    }

    @Test func publishesInsideAUnicodeFolderWithSpaces() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appendingPathComponent("Team café assets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let output = folder.appendingPathComponent("image.png")
        let bytes = Data("complete image".utf8)

        try BatchOutputFiles.publish(bytes, to: output)

        #expect(try Data(contentsOf: output) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["image.png"])
    }

    @Test func cancellationBeforeCommitPublishesNothing() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("image.png")

        #expect(throws: CancellationError.self) {
            try BatchOutputFiles.publish(Data("new image".utf8), to: output) {
                throw CancellationError()
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
