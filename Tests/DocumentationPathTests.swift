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
        // Recursive on purpose: ADRs live under `docs/decisions/`, and a flat listing
        // would silently exempt every nested document from the path contract.
        let documentationDirectory = repositoryRoot.appending(path: "docs")
        var documentation: [URL] = []
        if let enumerator = FileManager.default.enumerator(
            at: documentationDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        {
            while let url = enumerator.nextObject() as? URL {
                if url.pathExtension == "md" { documentation.append(url) }
            }
        }
        return rootDocuments + documentation.sorted { $0.path < $1.path }
    }
}
