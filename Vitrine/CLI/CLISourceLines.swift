import Foundation
import VitrineRendering

/// `--lines`: renders one span of a source while keeping the file's line numbers.
enum CLISourceLines {
    /// Keeps only `span` of the loaded text. A span that runs past the end stops at the
    /// last line; one that starts past it is refused, since nothing would be drawn.
    static func slice(
        _ loaded: FileInputLoader.LoadedFile, to span: ClosedRange<Int>?
    ) throws -> FileInputLoader.LoadedFile {
        guard let span else { return loaded }
        // Rows end at U+000A only, as `LineSplitter.lineCount` and the renderer's redaction
        // count them; a lone `\r` or U+2028 stays inside its row.
        var lines = loaded.text.components(separatedBy: "\n")
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        guard span.lowerBound <= lines.count else {
            throw CLIError.sourceLinesOutOfRange(first: span.lowerBound, lineCount: lines.count)
        }
        var sliced = loaded
        let upper = min(span.upperBound, lines.count)
        sliced.text = lines[(span.lowerBound - 1)..<upper].joined(separator: "\n")
        return sliced
    }

    /// Maps file line ranges onto the rendered rows of `span`, dropping lines outside it.
    static func rows(
        _ fileRanges: [ClosedRange<Int>], in span: ClosedRange<Int>?
    ) -> [ClosedRange<Int>] {
        guard let span else { return fileRanges }
        let offset = span.lowerBound - 1
        return fileRanges.compactMap { range in
            let lower = max(range.lowerBound, span.lowerBound)
            let upper = min(range.upperBound, span.upperBound)
            return lower <= upper ? (lower - offset)...(upper - offset) : nil
        }
    }
}

/// Where a capture comes from, read from the file system without running Git: the
/// enclosing work tree's folder name and its current branch. Full paths never reach the image.
enum CLISourceOrigin {
    /// The nearest folder at or above `directory` that holds a `.git` entry.
    static func repositoryRoot(containing directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while true {
            let marker = candidate.appendingPathComponent(".git").path
            if FileManager.default.fileExists(atPath: marker) { return candidate }
            // `/` has one component; going past it would climb `/..` forever.
            guard candidate.pathComponents.count > 1 else { return nil }
            candidate = candidate.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// The branch `HEAD` names, following a linked worktree's `gitdir:` file. A detached
    /// `HEAD` has none.
    static func branch(atRepositoryRoot root: URL) -> String? {
        var gitDirectory = root.appendingPathComponent(".git")
        if let pointer = try? String(contentsOf: gitDirectory, encoding: .utf8),
            pointer.hasPrefix("gitdir:")
        {
            let path = pointer.dropFirst("gitdir:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = URL(fileURLWithPath: root.path, isDirectory: true)
            gitDirectory = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        }
        guard
            let head = try? String(
                contentsOf: gitDirectory.appendingPathComponent("HEAD"), encoding: .utf8)
        else { return nil }
        let reference = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        guard reference.hasPrefix(prefix) else { return nil }
        return String(reference.dropFirst(prefix.count))
    }

    /// `weather-app — ForecastClient.swift`, or the file name alone outside a work tree.
    static func windowTitle(forFile path: String) -> String {
        let file = URL(fileURLWithPath: path)
        guard let root = repositoryRoot(containing: file.deletingLastPathComponent()) else {
            return file.lastPathComponent
        }
        return "\(root.lastPathComponent) — \(file.lastPathComponent)"
    }

    /// The `vgrab` header label: the work tree's (or folder's) name and the current branch.
    static func projectLabel(directory: URL) -> String {
        let root = repositoryRoot(containing: directory)
        let name = (root ?? directory.standardizedFileURL).lastPathComponent
        let project = name.isEmpty ? "/" : name
        guard let root, let branch = branch(atRepositoryRoot: root) else { return project }
        return "\(project) · \(branch)"
    }
}
