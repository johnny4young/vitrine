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
    /// `HEAD`, a reftable placeholder (`.invalid`) or an unreadable file has none.
    static func branch(atRepositoryRoot root: URL) -> String? {
        var gitDirectory = root.appendingPathComponent(".git")
        if let pointer = firstLine(of: gitDirectory), pointer.hasPrefix("gitdir:") {
            let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            let base = URL(fileURLWithPath: root.path, isDirectory: true)
            gitDirectory = URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        }
        guard let head = firstLine(of: gitDirectory.appendingPathComponent("HEAD")) else {
            return nil
        }
        let prefix = "ref: refs/heads/"
        guard head.hasPrefix(prefix) else { return nil }
        let branch = String(head.dropFirst(prefix.count))
        return branch.isEmpty || branch == ".invalid" ? nil : branch
    }

    /// The first line of a small regular file. FIFOs, devices, folders and anything over
    /// `limit` bytes are refused, so a hostile `.git` can't block or flood the CLI.
    static func firstLine(of url: URL, limit: Int = 4096) -> String? {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
            info.st_size <= limit
        else { return nil }
        var buffer = [UInt8](repeating: 0, count: limit)
        let count = read(descriptor, &buffer, limit)
        guard count >= 0 else { return nil }
        let text = String(decoding: buffer[..<count], as: UTF8.self)
        return text.split(separator: "\n", omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// A folder's name, unless it is the home folder or `/`, whose name is the account's or
    /// says nothing.
    private static func shareableName(of folder: URL) -> String? {
        let path = folder.resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
        guard path != home, path != "/", !folder.lastPathComponent.isEmpty else { return nil }
        return folder.lastPathComponent
    }

    /// `weather-app — ForecastClient.swift`, or the file name alone outside a work tree.
    static func windowTitle(forFile path: String) -> String {
        let file = URL(fileURLWithPath: path)
        guard let root = repositoryRoot(containing: file.deletingLastPathComponent()),
            let project = shareableName(of: root)
        else { return file.lastPathComponent }
        return "\(project) — \(file.lastPathComponent)"
    }

    /// The `vgrab` header label: the work tree's (or folder's) name and the current branch.
    /// Nil when the only name available is the home folder's or `/`.
    static func projectLabel(directory: URL) -> String? {
        let root = repositoryRoot(containing: directory)
        let project = shareableName(of: root ?? directory.standardizedFileURL)
        let branch = root.flatMap(branch(atRepositoryRoot:))
        return switch (project, branch) {
        case (let project?, let branch?): "\(project) · \(branch)"
        case (let project?, nil): project
        case (nil, let branch?): branch
        case (nil, nil): nil
        }
    }
}
