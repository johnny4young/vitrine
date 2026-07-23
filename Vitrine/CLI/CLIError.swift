import Foundation

/// A problem the CLI reports to the user, mapped to a clear message and a process
/// exit code. Every failure mode the `render` command can hit has a case
/// here so the executable never prints a raw Swift error or crashes.
///
/// `nonisolated` so it is a plain `Sendable & Equatable` error: the executable throws
/// and catches it across isolation boundaries, and the test suite can assert on it
/// with Swift Testing's `#expect(throws:)` (which requires a `Sendable` error). Its
/// `message` composes the equally `nonisolated` `CLIUsage.text`.
nonisolated enum CLIError: Error, Equatable {
    /// `--help`/`-h` was requested: not an error, but it short-circuits parsing so
    /// the caller prints usage and exits successfully.
    case helpRequested
    /// No subcommand, or an unrecognized one, was given.
    case unknownCommand(String)
    /// A flag the parser does not recognize.
    case unknownFlag(String)
    /// A flag that needs a value was the last token (its value is missing).
    case missingValue(flag: String)
    /// A required positional/option was not supplied (e.g. the input file or `--out`).
    case missingRequired(String)
    /// A value was supplied but is not valid for its flag (bad number, unknown id…).
    case invalidValue(flag: String, value: String)
    /// Two otherwise-valid options were combined in a way that would be ambiguous.
    case incompatibleOptions(String)
    /// The input source file could not be read.
    case inputUnreadable(path: String)
    /// The input file decoded but is not text (likely a binary file).
    case inputNotText(path: String)
    /// The requested local Git diff could not be generated without exposing raw Git output.
    case gitDiffFailed
    /// Git completed successfully but the selected revision/pathspecs produced no diff.
    case gitDiffEmpty
    /// The generated diff exceeded the shared bounded source-input limit.
    case gitDiffTooLarge
    /// `--image` input decoded as bytes but is not an image supported by AppKit.
    case inputNotImage(path: String)
    /// Rendering produced no image (an internal renderer failure).
    case renderFailed
    /// An output path already exists and `--no-overwrite` requested a safe run.
    case outputExists(path: String)
    /// Encoding or writing the output file failed.
    case writeFailed(path: String)
    /// A batch found no renderable inputs and `--fail-on-empty` requested a failing exit.
    case batchEmpty(skipped: Int)
    /// A batch completed at least some work, but `--fail-on-skipped` requested a
    /// failing exit when unreadable/non-text files were skipped.
    case batchSkipped(rendered: Int, skipped: Int)
    /// `--edit` could not open Vitrine to receive the handoff (no app registered for the
    /// `vitrine://` scheme, or a Launch Services failure). Surfaced so a script sees a
    /// non-zero exit instead of a false success.
    case editorOpenFailed
    /// The PRO tier is required for command-line/automation rendering but is not
    /// active. Reported before any file work so a free build never renders.
    case proRequired

    /// A short, human-readable explanation suitable for stderr.
    var message: String {
        switch self {
        case .helpRequested:
            CLIUsage.text
        case .unknownCommand(let command):
            "Unknown command \"\(command)\". The commands are \"render\", \"multi-size\", \"batch\", \"list\", \"shell-init\", and \"version\"."
        case .unknownFlag(let flag):
            "Unknown option \"\(flag)\"."
        case .missingValue(let flag):
            "Option \"\(flag)\" needs a value."
        case .missingRequired(let what):
            "Missing required \(what)."
        case .invalidValue(let flag, let value):
            "\"\(value)\" is not a valid value for \"\(flag)\"."
        case .incompatibleOptions(let message):
            message
        case .inputUnreadable(let path):
            "Could not read the input file at \"\(path)\"."
        case .inputNotText(let path):
            "The input file at \"\(path)\" is not text."
        case .gitDiffFailed:
            "Could not generate the local Git diff. Check the revision and repository."
        case .gitDiffEmpty:
            "The selected Git revision and paths produced an empty diff."
        case .gitDiffTooLarge:
            "The generated Git diff is too large to render (maximum 5 MB)."
        case .inputNotImage(let path):
            "The input file at \"\(path)\" is not a supported image."
        case .renderFailed:
            "Rendering failed to produce an image."
        case .outputExists(let path):
            "The output already exists at \"\(path)\". Remove it or omit --no-overwrite."
        case .writeFailed(let path):
            "Could not write the output to \"\(path)\"."
        case .batchEmpty(let skipped):
            "Batch found no renderable input files"
                + (skipped > 0 ? " (skipped \(skipped) file\(skipped == 1 ? "" : "s"))" : "")
                + "."
        case .batchSkipped(let rendered, let skipped):
            "Batch rendered \(rendered) image\(rendered == 1 ? "" : "s") but skipped "
                + "\(skipped) file\(skipped == 1 ? "" : "s")."
        case .editorOpenFailed:
            "Could not open Vitrine to receive the output. Is Vitrine installed?"
        case .proRequired:
            "Vitrine PRO is required for command-line and automation rendering. "
                + "Activate PRO in the Vitrine app to unlock it."
        }
    }

    /// The process exit code this failure maps to. `0` is reserved for success and
    /// for the help request (which is not a failure); every genuine error is `1`.
    var exitCode: Int32 {
        switch self {
        case .helpRequested: 0
        default: 1
        }
    }
}
