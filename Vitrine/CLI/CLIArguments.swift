import Foundation

/// Parses `vitrine` command-line arguments into a `CLIOptions`.
///
/// The grammar is deliberately tiny and dependency-free (no third-party arg parser):
/// a constrained free `terminal-capture` or general `render`, `multi-size`, and `batch`
/// subcommand, one positional input path/folder, a command-specific output contract,
/// and boolean / `--flag value` options. Pure
/// inspection commands such as `list`, `recipe`, and `shell-init` are handled before
/// this parser so they can run without AppKit or the capability gate. Keeping the parser
/// hand-rolled means the CLI adds no new package to the app and remains straightforward
/// to unit-test.
///
/// Unknown flags, missing values, and bad enum/number values all throw a specific
/// `CLIError` so a docs/automation pipeline fails loudly with a clear message instead
/// of silently rendering the wrong thing.
///
/// Main-actor isolated (the module default) so it can read the main-actor model
/// catalogs (`ExportPreset`, `SettingsDefaults`) while validating ids and ranges. The
/// executable runs it from `main.swift`, whose top-level code is on the main actor.
@MainActor
enum CLIArguments {
    /// Parses the argument list *after* the executable name (that is,
    /// `CommandLine.arguments.dropFirst()`), returning one validated command contract.
    ///
    /// Throws `CLIError.helpRequested` for `--help`/`-h` (the caller prints usage),
    /// and a specific error for any malformed input.
    static func parse(_ arguments: [String]) throws -> CLIOptions {
        var parser = try CLIArgumentParser(arguments)
        return try parser.parse()
    }
}
