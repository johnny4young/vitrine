import Foundation
import Testing

/// Target ownership is a build-time contract, complementary to app/CLI behavior tests.
@Suite("Shared source ownership")
struct SharedSourceOwnershipTests {
    @Test func cliLinksSharedModulesInsteadOfCompilingAppAdapters() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
        let core = try #require(Self.targetLines("VitrineCLICore", in: project))
        #expect(Set(Self.values(of: "- path:", in: core)) == ["Vitrine/CLI", "VitrineCLI"])
        let dependencies = Set(Self.values(of: "- target:", in: core))
        #expect(dependencies == ["VitrineDomain", "VitrineRendering"])
    }

    /// The lines of one top-level target block, whatever order the targets are declared in.
    private static func targetLines(_ name: String, in project: String) -> [String]? {
        let lines = project.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(of: "  \(name):") else { return nil }
        let body = lines[(start + 1)...].prefix { line in
            line.isEmpty || line.hasPrefix("   ") || line.hasPrefix("  #")
        }
        return Array(body)
    }

    /// Values of `prefix` entries with YAML comments and quotes removed.
    private static func values(of prefix: String, in lines: [String]) -> [String] {
        lines.compactMap { line in
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard entry.hasPrefix(prefix) else { return nil }
            let value =
                entry.dropFirst(prefix.count).split(separator: "#", maxSplits: 1).first ?? ""
            return value.trimmingCharacters(
                in: .whitespaces.union(CharacterSet(charactersIn: "\"'")))
        }
    }
}
