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
        if let tracked = trackedDocuments() { return tracked }
        return enumeratedDocuments()
    }

    /// Only tracked documentation is under contract. Enumerating the filesystem also
    /// picks up gitignored, untracked files (a local design-sync mirror under
    /// `docs/design/`, for example) whose stale paths fail locally while CI stays green.
    private static func trackedDocuments() -> [URL]? {
        guard let gitExecutable = gitExecutable() else { return nil }
        let git = Process()
        git.executableURL = gitExecutable
        git.arguments = ["ls-files", "-z", "--", "README.md", "CONTRIBUTING.md", "docs"]
        git.currentDirectoryURL = repositoryRoot
        let stdout = Pipe()
        git.standardOutput = stdout
        git.standardError = FileHandle.nullDevice
        do { try git.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0,
            let listing = String(data: data, encoding: .utf8)
        else { return nil }
        let paths = listing.split(separator: "\0").map(String.init)
            .filter { $0.hasSuffix(".md") }
        guard !paths.isEmpty else { return nil }
        return paths.sorted().map { repositoryRoot.appending(path: $0) }
    }

    /// `/usr/bin/git` is an xcrun shim that refuses to run inside the App Sandbox the
    /// test host inherits, so resolve a real binary from the developer tools instead.
    private static func gitExecutable() -> URL? {
        var candidates: [String] = []
        if let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] {
            candidates.append(developerDirectory + "/usr/bin/git")
        }
        candidates += [
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(filePath: $0) }
    }

    /// Fallback when git is unavailable (or refuses to run): every `.md` on disk.
    private static func enumeratedDocuments() -> [URL] {
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
