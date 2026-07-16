import Foundation
import Testing

@testable import Vitrine

@MainActor
@Suite("Git diff CLI input")
struct GitDiffInputLoaderTests {
    @Test func parserBuildsABoundedDiffSourceAndEnablesBands() throws {
        let options = try CLIArguments.parse([
            "render", "--git-diff", "main...HEAD", "--git-path", "Sources/App.swift",
            "--git-path", "Tests", "--out", "review.png",
        ])

        #expect(options.inputPath.isEmpty)
        #expect(options.gitDiffRange == "main...HEAD")
        #expect(options.gitDiffPaths == ["Sources/App.swift", "Tests"])
        #expect(options.diffDecorations == true)
        let config = options.makeConfig(code: "diff --git a/x b/x", language: .diff)
        #expect(config.metadata.filename == "changes.diff")
    }

    @Test func explicitNoDiffBandsWinsAndSinglePathNamesMetadata() throws {
        let options = try CLIArguments.parse([
            "render", "--git-diff", "HEAD", "--git-path", "Sources/App.swift",
            "--no-diff-bands", "--out", "review.png",
        ])

        #expect(options.diffDecorations == false)
        let config = options.makeConfig(code: "diff", language: .diff)
        #expect(config.metadata.filename == "App.swift.diff")
    }

    @Test func parserRejectsAmbiguousOrOptionLikeDiffSources() {
        #expect(throws: CLIError.invalidValue(flag: "--git-diff", value: "--stat")) {
            try CLIArguments.parse([
                "render", "--git-diff", "--stat", "--out", "review.png",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--git-diff", value: "HEAD\n--stat")) {
            try CLIArguments.parse([
                "render", "--git-diff", "HEAD\n--stat", "--out", "review.png",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("--git-path requires --git-diff.")) {
            try CLIArguments.parse([
                "render", "--git-path", "Sources", "--out", "review.png",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine --git-diff with input file \"input.swift\".")
        ) {
            try CLIArguments.parse([
                "render", "input.swift", "--git-diff", "HEAD", "--out", "review.png",
            ])
        }
        #expect(
            throws: CLIError.incompatibleOptions("Cannot combine --git-diff with --stdin.")
        ) {
            try CLIArguments.parse([
                "render", "--stdin", "--git-diff", "HEAD", "--out", "review.png",
            ])
        }
        #expect(throws: CLIError.unknownFlag("--git-diff")) {
            try CLIArguments.parse([
                "batch", "Sources", "--git-diff", "HEAD", "--out", "review",
            ])
        }
    }

    @Test func invocationNeverUsesAShellAndSeparatesPathspecs() throws {
        let directory = URL(fileURLWithPath: "/tmp/example-repository", isDirectory: true)
        var captured: GitDiffInputLoader.Invocation?
        let loaded = try GitDiffInputLoader.load(
            range: "HEAD~1..HEAD", paths: ["Sources", "--option-like-name"],
            currentDirectoryURL: directory,
            executor: { invocation in
                captured = invocation
                return GitDiffInputLoader.ExecutionResult(
                    terminationStatus: 0,
                    standardOutput: Data("diff --git a/a b/a\n-old\n+new\n".utf8))
            })

        #expect(captured?.executableURL.path == "/usr/bin/git")
        #expect(captured?.currentDirectoryURL == directory)
        #expect(
            captured?.arguments == [
                "--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--no-color",
                "HEAD~1..HEAD", "--src-prefix=a/", "--dst-prefix=b/", "--unified=3", "--",
                "Sources", "--option-like-name",
            ])
        #expect(loaded.language == .diff)
        #expect(loaded.filename == "changes.diff")
        #expect(GitDiffInputLoader.environmentOverrides["GIT_LITERAL_PATHSPECS"] == "1")
        #expect(GitDiffInputLoader.environmentOverrides["GIT_NO_LAZY_FETCH"] == "1")
        #expect(GitDiffInputLoader.environmentOverrides["GIT_OPTIONAL_LOCKS"] == "0")
        #expect(GitDiffInputLoader.environmentOverrides["GIT_PAGER"] == "cat")
        #expect(GitDiffInputLoader.environmentOverrides["GIT_TERMINAL_PROMPT"] == "0")
        #expect(GitDiffInputLoader.environmentOverrides["LC_ALL"] == "C")
        #expect(
            GitDiffInputLoader.scrubbedEnvironmentKeys
                == ["GIT_DIFF_OPTS", "GIT_EXTERNAL_DIFF"])
    }

    @Test func loaderMapsGitEmptyAndOversizedResultsPrecisely() {
        #expect(throws: GitDiffInputLoader.LoadError.gitFailed) {
            try GitDiffInputLoader.load(range: "missing", paths: []) { _ in
                GitDiffInputLoader.ExecutionResult(
                    terminationStatus: 128, standardOutput: Data())
            }
        }
        #expect(throws: GitDiffInputLoader.LoadError.emptyDiff) {
            try GitDiffInputLoader.load(range: "HEAD", paths: []) { _ in
                GitDiffInputLoader.ExecutionResult(terminationStatus: 0, standardOutput: Data())
            }
        }
        #expect(throws: GitDiffInputLoader.LoadError.tooLarge) {
            try GitDiffInputLoader.load(range: "HEAD", paths: []) { _ in
                GitDiffInputLoader.ExecutionResult(
                    terminationStatus: 0,
                    standardOutput: Data(count: FileInputLoader.maximumByteCount + 1))
            }
        }
    }

}
