import Foundation
import Testing

/// VitrineCore layering gate (§8.2): the model + terminal layer must stay free of the
/// SwiftUI **view** layer, so the UI-free boundary the color/model refactor established
/// can't silently regress. Every `SwiftUI.Color`/`LinearGradient`/`Alignment`/environment
/// bridge lives in a `*+UI.swift` adapter in the UI layer instead of on the model type.
///
/// This turns the now-explicit layering into an *enforced* one — the same "docs/config as
/// tests" muscle the repo already uses for `ARCHITECTURE.md` module drift and the CI
/// workflow gates — without waiting on the physical `VitrineCore` SwiftPM package (which
/// would additionally give `swift test` without an app host). `Color+Hex.swift` is the one
/// intentional exception: it *is* the `RGBAColor` ⇄ `SwiftUI.Color` bridge.
@Suite("Model layer stays SwiftUI-free · §8.2")
struct ModelLayerPurityTests {
    /// The repository root, anchored to this file (`<repo>/Tests/…`).
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// Files allowed to import SwiftUI within the model layer — the documented bridges.
    private static let allowed: Set<String> = ["Color+Hex.swift"]

    @Test func modelAndTerminalLayersDoNotImportSwiftUI() throws {
        let fileManager = FileManager.default
        for directory in ["Models", "Terminal"] {
            let base = Self.repositoryRoot
                .appendingPathComponent("Vitrine")
                .appendingPathComponent(directory)
            let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: nil)
            var swiftFiles: [URL] = []
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { swiftFiles.append(url) }
            }
            #expect(!swiftFiles.isEmpty, "Expected Swift files under Vitrine/\(directory)")

            for file in swiftFiles where !Self.allowed.contains(file.lastPathComponent) {
                let source = try String(contentsOf: file, encoding: .utf8)
                let importsSwiftUI =
                    source
                    .components(separatedBy: .newlines)
                    .contains { $0.trimmingCharacters(in: .whitespaces) == "import SwiftUI" }
                #expect(
                    !importsSwiftUI,
                    """
                    \(directory)/\(file.lastPathComponent) must not import SwiftUI — the model \
                    layer stays UI-free; move the bridge to a *+UI.swift adapter in the UI layer \
                    (§8.2 VitrineCore).
                    """
                )
            }
        }
    }
}
