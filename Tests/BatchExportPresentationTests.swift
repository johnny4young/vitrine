import Foundation
import Testing

@testable import Vitrine

@Suite("Batch export presentation")
@MainActor
struct BatchExportPresentationTests {
    @Test func routesDirectorySelectionAndRevealThroughInjectedOperations() {
        let expectedDirectory = URL(fileURLWithPath: "/tmp/vitrine-batch-export")
        var selectionMessages: [String] = []
        var revealedDirectories: [URL] = []
        let presentation = BatchExportPresentation(
            selectDirectory: { message in
                selectionMessages.append(message)
                return expectedDirectory
            },
            revealDirectory: { revealedDirectories.append($0) })

        let selected = presentation.chooseDirectory(message: "Choose a destination")
        presentation.reveal(expectedDirectory)

        #expect(selected == expectedDirectory)
        #expect(selectionMessages == ["Choose a destination"])
        #expect(revealedDirectories == [expectedDirectory])
    }

    @Test func noOpPresentationCancelsSelectionSafely() {
        #expect(BatchExportPresentation.noOp.chooseDirectory(message: "Choose") == nil)
        BatchExportPresentation.noOp.reveal(URL(fileURLWithPath: "/tmp"))
    }

    @Test func completeBatchRequiresEveryExpectedOutput() {
        let completion = BatchExportCompletion(written: 3, failed: 0, expected: 3)

        #expect(completion.isComplete)
        #expect(completion.failureNote == nil)
    }

    @Test func missingOutputIsIncompleteEvenWhenFailureCountIsZero() throws {
        let completion = BatchExportCompletion(written: 2, failed: 0, expected: 3)
        let note = try #require(completion.failureNote)

        #expect(!completion.isComplete)
        #expect(note.hasPrefix("2/3 — "))
    }

    @Test(arguments: [
        (written: 2, failed: 1, expected: 3),
        (written: 3, failed: 1, expected: 3),
        (written: 0, failed: 0, expected: 0),
    ])
    func failedOrEmptyBatchRemainsIncomplete(
        counts: (written: Int, failed: Int, expected: Int)
    ) {
        let completion = BatchExportCompletion(
            written: counts.written,
            failed: counts.failed,
            expected: counts.expected)

        #expect(!completion.isComplete)
        #expect(completion.failureNote != nil)
    }

    @Test func batchExportSheetsDoNotDiscoverAppOwnedPresentation() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "Vitrine/Export/MultiSizeExportView.swift",
            "Vitrine/Export/CarouselExportView.swift",
        ]

        for relativePath in relativePaths {
            let source = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8)
            let code = sourceCodeWithoutLineComments(source)

            for forbiddenDependency in [
                "NSOpenPanel",
                "NSWorkspace.shared",
                "CaptureHUDController.shared",
            ] {
                #expect(
                    !code.contains(forbiddenDependency),
                    "\(relativePath) must receive \(forbiddenDependency) as an operation")
            }
        }
    }
}
