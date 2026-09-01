import Foundation
import Testing

@Suite("Documentation source paths")
struct DocumentationPathTests {
    @Test func exactBacktickedSwiftPathsResolve() throws {
        let documents = try Self.documentsToCheck()
        let expression = try NSRegularExpression(
            pattern:
                #"`((?:Vitrine(?:Domain|Rendering|CLI|MenuBarHelper)?|Tests|DomainTests|RenderingTests|UITests)/[A-Za-z0-9_+./-]+\.swift)`"#
        )
        var missing: [String] = []

        for document in documents {
            let contents = try String(contentsOf: document, encoding: .utf8)
            let range = NSRange(contents.startIndex..., in: contents)
            for match in expression.matches(in: contents, range: range) {
                guard
                    let captureRange = Range(match.range(at: 1), in: contents)
                else { continue }
                let relativePath = String(contents[captureRange])
                guard
                    !FileManager.default.fileExists(
                        atPath: Self.repositoryRoot.appending(path: relativePath).path)
                else { continue }
                let documentPath = document.path.replacingOccurrences(
                    of: Self.repositoryRoot.path + "/", with: "")
                missing.append("\(documentPath): \(relativePath)")
            }
        }

        #expect(
            missing.isEmpty,
            "Every exact backticked Swift path must resolve:\n\(missing.sorted().joined(separator: "\n"))"
        )
    }

    private static var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func documentsToCheck() throws -> [URL] {
        let rootDocuments = ["README.md", "CONTRIBUTING.md"].map {
            repositoryRoot.appending(path: $0)
        }
        let documentationDirectory = repositoryRoot.appending(path: "docs")
        let documentation = try FileManager.default.contentsOfDirectory(
            at: documentationDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "md" }
        return rootDocuments + documentation
    }
}
