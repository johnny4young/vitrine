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
        /// The command's own exit status, like `vgrab`, so `vitrine run make && …` composes,
        /// even when the capture could not be rendered.
        var status: Int32
        var summary: String
        /// Why the capture wasn't copied or opened, for stderr.
        var renderError: String?
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
        status; a command killed by a signal exits with the signal's number, as `script` reports.
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
        let scratch = try CLIRunScratch()
        defer { scratch.finish() }

        var childEnvironment = environment
        // Best effort, as with `vgrab -w`: tools that ask the tty directly ignore it.
        if let columns = invocation.options.terminalColumns {
            childEnvironment["COLUMNS"] = String(columns)
        }
        let status = try execute(scratch.capture, invocation.command, childEnvironment)

        var options = invocation.options
        options.inputPath = scratch.capture.path
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
        do {
            return Outcome(status: status, summary: try render(options))
        } catch let error as CLIError {
            return Outcome(status: status, summary: "", renderError: error.message)
        }
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

    /// Starts `script` in this process group, as a shell would, so it can own the terminal
    /// while the command runs; a child in its own group would stop on its first tty access.
    nonisolated static func runUnderPseudoTerminal(
        capture: URL, command: [String], environment: [String: String]
    ) throws -> Int32 {
        let path = "/usr/bin/script"
        let argv = ([path, "-q", "-e", capture.path] + command).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }

        // The CLI ignores these while it cleans up; the child gets the defaults back.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for signal in CLIRunScratch.signals { sigaddset(&defaults, signal) }
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF))

        var child: pid_t = 0
        guard posix_spawn(&child, path, nil, &attributes, argv, envp) == 0 else {
            throw CLIError.commandNotFound(path)
        }
        var status: Int32 = 0
        while waitpid(child, &status, 0) == -1 {
            guard errno == EINTR else { throw CLIError.renderFailed }
        }
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
    }
}

/// The run's private folder (0700) and capture file (0600). An interrupted CLI removes them
/// before dying of the same signal, so no transcript is left behind.
nonisolated final class CLIRunScratch {
    static let signals = [SIGHUP, SIGINT, SIGTERM]

    let directory: URL
    let capture: URL
    private let sources: [any DispatchSourceSignal]
    private let previousHandlers: [sig_t?]

    init(onSignal: @escaping @Sendable (Int32) -> Void = CLIRunScratch.terminate) throws {
        var template = Array(
            (FileManager.default.temporaryDirectory.path + "/vitrine-run-XXXXXX").utf8CString)
        guard let created = mkdtemp(&template) else {
            throw CLIError.writeFailed(path: FileManager.default.temporaryDirectory.path)
        }
        let directory = URL(fileURLWithPath: String(cString: created), isDirectory: true)
        self.directory = directory
        capture = directory.appendingPathComponent("capture.log")
        guard
            FileManager.default.createFile(
                atPath: capture.path, contents: nil, attributes: [.posixPermissions: 0o600])
        else {
            try? FileManager.default.removeItem(at: directory)
            throw CLIError.writeFailed(path: capture.path)
        }
        previousHandlers = Self.signals.map { signal($0, SIG_IGN) }
        sources = Self.signals.map { number in
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler {
                try? FileManager.default.removeItem(at: directory)
                onSignal(number)
            }
            source.resume()
            return source
        }
    }

    func finish() {
        for source in sources { source.cancel() }
        for (number, handler) in zip(Self.signals, previousHandlers) { signal(number, handler) }
        try? FileManager.default.removeItem(at: directory)
    }

    static func terminate(_ number: Int32) {
        signal(number, SIG_DFL)
        raise(number)
    }
}
