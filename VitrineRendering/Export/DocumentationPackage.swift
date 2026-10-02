import Foundation
import VitrineDomain

/// Already-rendered image plus safe, relative-link representations. No filesystem effects.
public struct DocumentationPackage: Sendable {
    public nonisolated let files: [String: Data]

    public init(
        config: SnapshotConfig, png: Data, representations: Set<DocumentationRepresentation>
    ) {
        var files = ["image.png": png]
        if representations.contains(.markdown) {
            files["README.md"] = Data(
                MarkdownExport.document(for: config, imageSource: "image.png").utf8)
        }
        if representations.contains(.html) {
            files["index.html"] = Data(
                HTMLExport.document(for: config, imageSource: "image.png").utf8)
        }
        if representations.contains(.text), !config.usesImageContent {
            files["source.txt"] = Data(config.sidecarText.utf8)
        }
        self.files = files
    }
}
