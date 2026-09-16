import Foundation
import Testing

/// `AppSettings.style` is the render configuration without the document text, so the
/// `SnapshotConfig` members computed from that text answer as if the document were
/// empty when read through it: `style.hasRenderableContent` is false for any code
/// document. Code that needs those answers reads `config`, `documentIsEmpty`, or
/// `hasRenderableContent` on the settings instead. The mistake compiles, so this guard
/// catches it.
@Suite("Style facade contract")
struct StyleFacadeContractTests {
    /// The repository root, anchored to this file (`<repo>/RepositoryTests/…`).
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test func appCodeNeverReadsDocumentDerivedMembersThroughTheStyleFacade() throws {
        let documentDerived = try Regex(
            #"\.style\.(code|hasRenderableContent|sidecarText|richClipboardText)\b"#)
        let base = Self.repositoryRoot.appendingPathComponent("Vitrine")
        let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        var scanned = 0
        var offenders: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in source.components(separatedBy: .newlines).enumerated()
            where line.contains(documentDerived) {
                offenders.append("\(url.lastPathComponent):\(number + 1): \(line)")
            }
        }

        #expect(scanned > 100, "expected to scan the app's Swift sources")
        #expect(offenders.isEmpty, "document-derived members read through style: \(offenders)")
    }
}
