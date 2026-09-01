import Foundation
import Testing

/// The portable domain must stay free of Apple UI frameworks so command-line policies and
/// hostless tests cannot silently acquire a window-server or rendering dependency.
///
/// Rendering-specific AppKit/SwiftUI bridges live in `VitrineRendering`; this source contract
/// complements the Xcode target dependency by failing if a domain file imports one directly.
@Suite("Domain layer stays UI-free")
struct ModelLayerPurityTests {
    /// The repository root, anchored to this file (`<repo>/Tests/…`).
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    @Test func domainDoesNotImportUIFrameworks() throws {
        let fileManager = FileManager.default
        let base = Self.repositoryRoot.appendingPathComponent("VitrineDomain")
        let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: nil)
        var swiftFiles: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { swiftFiles.append(url) }
        }
        #expect(!swiftFiles.isEmpty, "Expected Swift files under VitrineDomain")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let imports = Set(
                source.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("import ") })
            for forbidden in ["import SwiftUI", "import AppKit", "import WebKit"] {
                #expect(
                    !imports.contains(forbidden),
                    "\(file.lastPathComponent) must not use \(forbidden); keep UI in VitrineRendering or Vitrine"
                )
            }
        }
    }
}
