import Foundation
import Testing

/// The portable domain must stay free of platform and UI frameworks so command-line
/// policies and hostless tests cannot silently acquire a window-server, rendering, or
/// codec dependency.
///
/// This is an **allowlist**, not a blocklist. A blocklist of three UI frameworks let
/// `import ImageIO` (a runtime codec-capability probe) live in the domain unnoticed;
/// naming what *is* allowed means any new framework has to be argued for here.
/// Rendering-specific AppKit/SwiftUI/ImageIO bridges live in `VitrineRendering`; this
/// source contract complements the Xcode target dependency by failing when a domain
/// file imports anything else.
@Suite("Domain layer stays UI-free")
struct ModelLayerPurityTests {
    /// The repository root, anchored to this file (`<repo>/Tests/…`).
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }

    /// Frameworks a domain file may import, and why each earns its place:
    /// - Foundation: the module's baseline.
    /// - CoreGraphics: `CGFloat`/`CGSize`/`CGPoint`/`CGRect` geometry and
    ///   `CGColorSpace` names are value vocabulary, not rendering.
    /// - Compression: share-link payload codec (pure bytes in, bytes out).
    /// - Darwin: `inet_aton`/`inet_pton` address parsing and descriptor-level bounded
    ///   file reads (`open`/`fstat`) — POSIX, not Apple UI.
    private static let allowedImports: Set<String> = [
        "Foundation", "CoreGraphics", "Compression", "Darwin",
    ]

    @Test func domainImportsOnlyAllowlistedFrameworks() throws {
        let fileManager = FileManager.default
        let base = Self.repositoryRoot.appendingPathComponent("VitrineDomain")
        let enumerator = fileManager.enumerator(at: base, includingPropertiesForKeys: nil)
        var swiftFiles: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { swiftFiles.append(url) }
        }
        #expect(!swiftFiles.isEmpty, "Expected Swift files under VitrineDomain")

        var offenders: [String] = []
        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                // `import Foo` / `import struct Foo.Bar` / `@testable import Foo`
                let module =
                    trimmed.dropFirst("import ".count)
                    .split(whereSeparator: { $0 == " " || $0 == "." })
                    .filter {
                        !["struct", "class", "enum", "func", "var", "let", "protocol", "typealias"]
                            .contains(String($0))
                    }
                    .first.map(String.init) ?? ""
                if !Self.allowedImports.contains(module) {
                    offenders.append("\(file.lastPathComponent): \(trimmed)")
                }
            }
        }
        let allowed = Self.allowedImports.sorted().joined(separator: ", ")
        let listed = offenders.sorted().joined(separator: "\n")
        #expect(
            offenders.isEmpty,
            """
            VitrineDomain may import only \(allowed). Move platform/UI work to \
            VitrineRendering or Vitrine, or add the framework to the allowlist with a reason:
            \(listed)
            """
        )
    }
}
