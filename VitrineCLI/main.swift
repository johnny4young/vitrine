import AppKit
import Foundation

/// `vitrine` — the command-line renderer entry point.
///
/// ## Hosting strategy
///
/// `ImageRenderer` and Highlightr require AppKit on the **main actor**, so a plain
/// SwiftPM executable that never starts AppKit is not sufficient. Rather than driving
/// a separate headless helper, this tool *is* a minimal AppKit host: it creates the
/// shared `NSApplication`, sets the **accessory** activation policy (no Dock icon, no
/// app-switcher entry, no menu bar), registers the bundled fonts, renders on the main
/// actor through the unchanged `CLIRenderer`/`ExportManager` path, and exits. It never
/// presents a window and never calls `app.run()`, so there is no UI and no event loop
/// to get stuck in — the process does its work synchronously and terminates with a
/// conventional exit code.
///
/// This keeps CLI output pixel-identical to the GUI (same render pipeline, same
/// fonts) while needing no network, screen recording, or Accessibility permissions —
/// code rendering is fully local.
///
/// `main.swift` top-level code runs on the main actor under the module's
/// MainActor-default isolation, so the `@MainActor` renderer is called directly.

/// Writes a line to standard error without buffering surprises.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// `--version` and `shell-init` are pure metadata/text commands — no rendering, so
// they need neither AppKit nor the PRO gate. Handle them before anything else and exit.
let rawArguments = Array(CommandLine.arguments.dropFirst())
if let versionInvocation = CLIVersion.invocation(for: rawArguments) {
    switch versionInvocation {
    case .help:
        print(CLIVersion.usage)
        exit(0)
    case .version(let format):
        print(CLIVersion.output(format: format), terminator: "")
        exit(0)
    case .unknownFlag(let flag):
        printError("error: unknown version option \"\(flag)\".\n\n" + CLIVersion.usage)
        exit(2)
    case .extraArguments(let extras):
        printError(
            "error: unexpected argument(s) \"\(extras.joined(separator: " "))\" after version.\n\n"
                + CLIVersion.usage)
        exit(2)
    }
}

if rawArguments.first == "shell-init" {
    switch ShellInit.invocation(for: Array(rawArguments.dropFirst())) {
    case .help:
        print(ShellInit.usage)
        exit(0)
    case .snippet(let shell):
        print(ShellInit.snippet(for: shell))
        exit(0)
    case .unknownShell(let name):
        FileHandle.standardError.write(
            Data("error: unknown shell \"\(name)\". Use zsh, bash, or fish.\n".utf8))
        exit(2)
    case .extraArguments(let extras):
        FileHandle.standardError.write(
            Data(
                """
                error: unexpected argument(s) "\(extras.joined(separator: " "))" after shell-init. \
                Usage: vitrine shell-init [zsh|bash|fish]

                """.utf8))
        exit(2)
    }
}

// Catalog listing is also pure metadata: it prints the local ids accepted by the
// renderer options, so it should not initialize AppKit or require the PRO render gate.
if rawArguments.first == "list" {
    switch CLICatalog.invocation(for: Array(rawArguments.dropFirst())) {
    case .help:
        print(CLICatalog.usage)
        exit(0)
    case .listing(let catalog, let format):
        print(CLICatalog.output(for: catalog, format: format), terminator: "")
        exit(0)
    case .unknownCatalog(let name):
        printError("error: unknown catalog \"\(name)\".\n\n" + CLICatalog.usage)
        exit(2)
    case .unknownFlag(let flag):
        printError("error: unknown list option \"\(flag)\".\n\n" + CLICatalog.usage)
        exit(2)
    case .extraArguments(let extras):
        printError(
            "error: unexpected argument(s) \"\(extras.joined(separator: " "))\" after list.\n\n"
                + CLICatalog.usage)
        exit(2)
    }
}

// Recipe inspection is also local metadata work. Keep it outside AppKit and the
// render entitlement gate so scripts can validate configuration during setup.
if rawArguments.first == "recipe" {
    switch CLIRecipeCommand.invocation(for: Array(rawArguments.dropFirst())) {
    case .help:
        print(CLIRecipeCommand.usage)
        exit(0)
    case .run(let action, let path, let format):
        do {
            print(
                try CLIRecipeCommand.output(action: action, path: path, format: format),
                terminator: "")
            exit(0)
        } catch let error as CLIError {
            printError("error: " + error.message)
            exit(error.exitCode)
        } catch {
            printError("error: \(error)")
            exit(1)
        }
    case .unknownAction(let action):
        printError("error: unknown recipe action \"\(action)\".\n\n" + CLIRecipeCommand.usage)
        exit(2)
    case .unknownFlag(let flag):
        printError("error: unknown recipe option \"\(flag)\".\n\n" + CLIRecipeCommand.usage)
        exit(2)
    case .extraArguments(let extras):
        printError(
            "error: unexpected argument(s) \"\(extras.joined(separator: " "))\" after recipe path.\n\n"
                + CLIRecipeCommand.usage)
        exit(2)
    }
}

do {
    let options = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
    // Entitlement stays at the earliest process boundary. Authorization is lazy:
    // the constrained terminal-capture generated by `vgrab` never reads a PRO token,
    // while locked automation exits before AppKit, fonts, or source files are touched.
    try CLIEntitlement.authorize(options.command)

    // Bring up the shared application as a background accessory only after parsing
    // and authorization succeed. This initializes ImageRenderer/Highlightr without
    // showing a Dock icon, app-switcher entry, or menu bar.
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    // Register the bundled monospaced fonts that ship next to the executable so the
    // default font (JetBrains Mono) and every other bundled family render exactly as
    // in the GUI. Fonts live beside the development binary or in the app Resources.
    CLIFontRegistration.registerBundledFonts(in: CLIEnvironment.bundledFontsDirectory)

    let summary: String
    switch options.command {
    case .terminalCapture, .render:
        // `--edit` hands the source to the running editor (no render); otherwise the
        // normal render-and-write/copy path produces the image.
        summary =
            options.openInEditor
            ? try CLIRenderer.openInEditor(options) : try CLIRenderer.run(options)
    case .multiSize: summary = try CLIRenderer.runMultiSize(options)
    case .batch: summary = try CLIRenderer.runBatch(options)
    }
    if !options.quiet { print(summary) }
    exit(0)
} catch let error as CLIError {
    // `--help` is not a failure: print usage to stdout and exit cleanly.
    if case .helpRequested = error {
        print(error.message)
        exit(0)
    }
    printError("error: " + error.message)
    printError("")
    printError(CLIUsage.text)
    exit(error.exitCode)
} catch {
    printError("error: \(error)")
    exit(1)
}
