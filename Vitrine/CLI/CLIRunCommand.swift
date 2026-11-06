import Foundation

/// `vitrine run`: runs the command the user typed under a pseudo-terminal (the system
/// `script`, as `vgrab` does), then renders its output through the free terminal-capture
/// path. The output goes to a private temporary file that is removed afterwards.
enum CLIRunCommand {
    struct Invocation: Equatable {
        var options: CLIOptions
        var command: [String]
        var context = true
        /// `--title-from-command`: show the masked arguments, not only the program name.
        var titleFromCommand = false
    }

    struct Outcome: Equatable {
        /// The command's own exit status, like `vgrab`, so `vitrine run make && …` composes.
        var status: Int32
        var summary: String
    }

    static let usage = """
        vitrine run [--copy | --edit] [--terminal-width <n>] [--no-context] [--title-from-command]
                    [--redact-secrets] [--filename <text>] [--title <text>] [--conceal-clipboard]
                    [--] <command> [args…]

        Runs the command in a pseudo-terminal so it keeps its colors, shows its output as
        usual, then copies a terminal image of it (--copy is the default) or opens it in the
        editor (--edit). The image names the project, Git branch and program ("$ npm …")
        unless --no-context is given. --title-from-command shows the arguments too, with
        credential-shaped values masked. Nothing leaves this Mac. Exits with the command's
        status.
        """

    /// Splits options from the command and validates them before anything runs. Returns
    /// nil for `--help`. The command starts after `--` or at the first non-option word.
    static func invocation(for arguments: [String]) throws -> Invocation? {
        var tokens: [String] = []
        var context = true
        var titleFromCommand = false
        var index = arguments.startIndex
        while index < arguments.endIndex, arguments[index].hasPrefix("-") {
            let token = arguments[index]
            index += 1
            if token == "--" { break }
            if token == "--help" || token == "-h" { return nil }
            if token == "--no-context" {
                context = false
                continue
            }
            if token == "--title-from-command" {
                titleFromCommand = true
                continue
            }
            tokens.append(token)
            if case .value = CLIArgumentSchema.option(named: token)?.arity,
                index < arguments.endIndex
            {
                tokens.append(arguments[index])
                index += 1
            }
        }
        let command = Array(arguments[index...])
        let prefix = ["terminal-capture", "run-capture"]
        var options: CLIOptions
        do {
            options = try CLIArguments.parse(prefix + tokens)
        } catch CLIError.missingRequired("--copy or --edit") {
            options = try CLIArguments.parse(prefix + tokens + ["--copy"])
        }
        guard !command.isEmpty else { throw CLIError.missingRequired("command to run") }
        return Invocation(
            options: options, command: command, context: context,
            titleFromCommand: titleFromCommand)
    }

    /// Runs the command, then hands the capture to `render`. `execute` receives the capture
    /// file, the command, and its environment, and returns the exit status.
    static func perform(
        _ invocation: Invocation,
        directory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        execute: (URL, [String], [String: String]) throws -> Int32 = runUnderPseudoTerminal,
        render: (CLIOptions) throws -> String
    ) throws -> Outcome {
        guard executablePath(for: invocation.command[0], environment: environment) != nil else {
            throw CLIError.commandNotFound(invocation.command[0])
        }
        let capture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-run-\(UUID().uuidString).log")
        guard
            FileManager.default.createFile(
                atPath: capture.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else { throw CLIError.writeFailed(path: capture.path) }
        defer { try? FileManager.default.removeItem(at: capture) }

        var childEnvironment = environment
        // Best effort, as with `vgrab -w`: tools that ask the tty directly ignore it.
        if let columns = invocation.options.terminalColumns {
            childEnvironment["COLUMNS"] = String(columns)
        }
        let status = try execute(capture, invocation.command, childEnvironment)

        var options = invocation.options
        options.inputPath = capture.path
        if invocation.context, !options.openInEditor {
            options.metadataFilename =
                options.metadataFilename ?? CLISourceOrigin.projectLabel(directory: directory)
            // Arguments can hold credentials in shapes no rule foresees, so by default the
            // header names only the program; a `--title` the user typed is used as is.
            let command =
                invocation.titleFromCommand
                ? CLIRunHeader.command(invocation.command)
                : CLIRunHeader.program(invocation.command)
            options.metadataTitle = options.metadataTitle ?? "$ " + command
        }
        return Outcome(status: status, summary: try render(options))
    }

    /// The executable a bare name resolves to on `PATH`; a name with a slash is used as is.
    static func executablePath(for name: String, environment: [String: String]) -> String? {
        let manager = FileManager.default
        if name.contains("/") { return manager.isExecutableFile(atPath: name) ? name : nil }
        let directories = (environment["PATH"] ?? "").split(separator: ":")
        return
            directories
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name).path }
            .first { manager.isExecutableFile(atPath: $0) }
    }

    nonisolated static func runUnderPseudoTerminal(
        capture: URL, command: [String], environment: [String: String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "-e", capture.path] + command
        process.environment = environment
        do { try process.run() } catch { throw CLIError.commandNotFound("/usr/bin/script") }
        process.waitUntilExit()
        let status = process.terminationStatus
        return process.terminationReason == .uncaughtSignal ? 128 + status : status
    }
}
