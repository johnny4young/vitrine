import Foundation
import Testing

/// The CLI links no WebKit, and after the presenter seam was removed nothing stands
/// between the command surfaces and the WebKit-backed window: they name
/// `WebSnapshotWindowController.shared` directly. What keeps the headless tool clean is
/// therefore a property of the CLI target's source set — every directory that names the
/// controller is excluded from it.
///
/// A comment cannot enforce that, and the previous comment proved the point by naming a
/// directory that does not call the controller while omitting two that do. This derives
/// the calling directories from the sources instead, so adding a caller in a new
/// directory, or un-excluding an existing one, fails here rather than silently linking
/// WebKit into the tool.
@Suite("Web Snapshot CLI boundary")
struct WebSnapshotCLIBoundaryTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Top-level directories under `Vitrine/` that name the WebKit-backed window.
    private static func callingDirectories() throws -> Set<String> {
        let appRoot = repositoryRoot.appendingPathComponent("Vitrine", isDirectory: true)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: appRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
        var directories: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            guard
                sourceCodeWithoutLineComments(source).contains("WebSnapshotWindowController.shared")
            else { continue }
            let relative = url.path.replacingOccurrences(of: appRoot.path + "/", with: "")
            if let top = relative.split(separator: "/").first { directories.insert(String(top)) }
        }
        return directories
    }

    /// The CLI target's excluded directories, read from the project specification.
    private static func cliExcludedDirectories() throws -> Set<String> {
        let spec = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let start = try #require(spec.range(of: "\n  VitrineCLI:"))
        // The target's own block ends where the next top-level key begins.
        let rest = spec[start.upperBound...]
        let end = rest.range(of: "\n  ", options: [], range: rest.startIndex..<rest.endIndex)
        var body = String(rest)
        if let marker = rest.range(of: "\n  Vitrine") { body = String(rest[..<marker.lowerBound]) }
        _ = end
        var excluded: Set<String> = []
        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- \""), trimmed.hasSuffix("\"") else { continue }
            let name = trimmed.dropFirst(3).dropLast()
            if !name.contains("/") && !name.contains(".") { excluded.insert(String(name)) }
        }
        return excluded
    }

    @Test func everyDirectoryNamingTheWebKitWindowIsExcludedFromTheCLI() throws {
        let callers = try Self.callingDirectories()
        #expect(
            !callers.isEmpty, "the controller must be named somewhere, or this guard is vacuous")

        let excluded = try Self.cliExcludedDirectories()
        #expect(
            excluded.contains("WebRendering"),
            "the CLI must exclude the WebKit renderers themselves")

        for directory in callers.sorted() {
            #expect(
                excluded.contains(directory),
                "Vitrine/\(directory) names WebSnapshotWindowController, so the CLI target must exclude it"
            )
        }
    }
}
