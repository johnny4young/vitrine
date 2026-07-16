import Foundation

/// Loads a local Git diff as bounded, editor-ready source without invoking a shell.
///
/// Git receives a fixed argument vector: pagers, external diff drivers, textconv,
/// and color are disabled; user pathspecs are placed after `--`. Standard output is
/// drained incrementally so the child process cannot deadlock, and Git is stopped as
/// soon as output exceeds the shared 5 MB source cap.
enum GitDiffInputLoader {
    /// The bounded local change set Git should produce. Keeping this typed prevents
    /// `--cached` from ever travelling through the user-controlled revision slot.
    enum Source: Equatable, Sendable {
        case revision(String)
        case staged

        var arguments: [String] {
            switch self {
            case .revision(let range): [range]
            case .staged: ["--cached"]
            }
        }
    }

    static let defaultContextLines = 3
    static let contextLinesRange = 0...100
    static let environmentOverrides = [
        "GIT_LITERAL_PATHSPECS": "1",
        "GIT_NO_LAZY_FETCH": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_PAGER": "cat",
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
    ]
    static let scrubbedEnvironmentKeys: Set = ["GIT_DIFF_OPTS", "GIT_EXTERNAL_DIFF"]

    struct Invocation: Equatable {
        var executableURL: URL
        var arguments: [String]
        var currentDirectoryURL: URL
    }

    struct ExecutionResult {
        var terminationStatus: Int32
        var standardOutput: Data
    }

    enum LoadError: Error, Equatable {
        case gitFailed
        case emptyDiff
        case tooLarge
    }

    typealias Executor = @MainActor (Invocation) throws -> ExecutionResult

    /// Builds and executes a local `git diff`, returning the shared source-loader
    /// model so syntax detection, metadata, rendering, and sidecars stay unchanged.
    static func load(
        source: Source, paths: [String], contextLines: Int = defaultContextLines,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        executor: Executor = execute
    ) throws -> FileInputLoader.LoadedFile {
        precondition(contextLinesRange.contains(contextLines))
        let invocation = Invocation(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: [
                "--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--no-color",
                "--src-prefix=a/", "--dst-prefix=b/", "--unified=\(contextLines)",
            ] + source.arguments + ["--"] + paths,
            currentDirectoryURL: currentDirectoryURL)

        let result: ExecutionResult
        do {
            result = try executor(invocation)
        } catch let error as LoadError {
            throw error
        } catch {
            throw LoadError.gitFailed
        }

        guard result.terminationStatus == 0 else { throw LoadError.gitFailed }
        guard !result.standardOutput.isEmpty else { throw LoadError.emptyDiff }
        guard result.standardOutput.count <= FileInputLoader.maximumByteCount else {
            throw LoadError.tooLarge
        }

        do {
            return try FileInputLoader.decode(
                data: result.standardOutput, filename: defaultFilename(paths: paths))
        } catch FileInputLoader.LoadError.tooLarge {
            throw LoadError.tooLarge
        } catch {
            throw LoadError.gitFailed
        }
    }

    static func defaultFilename(paths: [String]) -> String {
        guard paths.count == 1 else { return "changes.diff" }
        let basename = URL(fileURLWithPath: paths[0]).lastPathComponent
        return basename.isEmpty ? "changes.diff" : "\(basename).diff"
    }

    /// Executes the fixed invocation while synchronously draining standard output.
    /// Reading starts immediately after launch, so Git cannot fill the pipe and block;
    /// the process is terminated as soon as one byte beyond the shared limit arrives.
    /// Child stderr is discarded, so repository paths or config diagnostics cannot
    /// leak through Vitrine's stable CLI errors.
    private static func execute(_ invocation: Invocation) throws -> ExecutionResult {
        let stdout = Pipe()
        let process = Process()
        process.executableURL = invocation.executableURL
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.currentDirectoryURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        for key in scrubbedEnvironmentKeys { environment[key] = nil }
        environment.merge(environmentOverrides) { _, override in override }
        process.environment = environment

        do {
            try process.run()
            // The child owns its duplicated descriptor after launch. Closing the
            // parent's writer lets the read side observe EOF when Git exits.
            try stdout.fileHandleForWriting.close()
        } catch {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            throw LoadError.gitFailed
        }
        defer { try? stdout.fileHandleForReading.close() }

        var output = Data()
        do {
            while output.count <= FileInputLoader.maximumByteCount {
                let remaining = FileInputLoader.maximumByteCount + 1 - output.count
                guard
                    let chunk = try stdout.fileHandleForReading.read(
                        upToCount: min(64 * 1024, remaining)),
                    !chunk.isEmpty
                else { break }
                output.append(chunk)
            }
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw LoadError.gitFailed
        }

        guard output.count <= FileInputLoader.maximumByteCount else {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw LoadError.tooLarge
        }

        process.waitUntilExit()
        return ExecutionResult(
            terminationStatus: process.terminationStatus, standardOutput: output)
    }
}
