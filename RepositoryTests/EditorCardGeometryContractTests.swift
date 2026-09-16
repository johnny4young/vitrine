import Foundation
import Testing

/// The editor's body never reads the preview card's measured size.
///
/// The size changes whenever the preview does. Read in `EditorView`'s body, directly or
/// through the stage's layout closures, every such change evaluated the whole editor a
/// second time: a padding step re-evaluated the editor, the inspector, and the code editor
/// twice. `PreviewCardStage` and the status capsule read it in their own bodies, and the
/// annotation actions read it when they run. Anything else is a new read in the editor's
/// body, and this fails before the double pass comes back.
@Suite("Editor card geometry contract")
struct EditorCardGeometryContractTests {
    /// The repository root, anchored to this file (`<repo>/RepositoryTests/…`).
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The only lines in the editor that may name the measured size: the writer and the
    /// two annotation actions.
    private static let allowedLines: Set<String> = [
        "cardGeometry.size = $0",
        "let copy = original.duplicated(in: cardGeometry.size, counterNumber: nextCounterNumber)",
        "settings.style.annotations[index].nudge(by: delta, in: cardGeometry.size)",
    ]

    @Test func onlyTheStageSubviewsAndTheAnnotationActionsReadTheCardSize() throws {
        let editor = Self.repositoryRoot.appendingPathComponent("Vitrine/Editor")
        let files = try FileManager.default.contentsOfDirectory(
            at: editor, includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("EditorView") && $0.pathExtension == "swift" }
        #expect(files.count > 3, "expected the EditorView sources")

        var found: Set<String> = []
        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (number, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains("cardGeometry.size") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if Self.allowedLines.contains(trimmed) {
                    found.insert(trimmed)
                } else {
                    offenders.append("\(file.lastPathComponent):\(number + 1): \(trimmed)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "read the card size inside PreviewCardStage or an action, not here: \(offenders)")
        #expect(found == Self.allowedLines, "an allowed line changed; update this contract")
    }
}
