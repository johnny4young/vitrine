import AppKit
import Foundation

/// `vitrine` — the command-line renderer entry point (CS-033).
///
/// ## Hosting strategy (decided per the CS-033 design note)
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

// `shell-init` only prints the shell integration text — no rendering, so it needs
// neither AppKit nor the PRO gate. Handle it before anything else and exit.
let rawArguments = Array(CommandLine.arguments.dropFirst())
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
            Data("error: unknown shell \"\(name)\". Use zsh or bash.\n".utf8))
        exit(2)
    case .extraArguments(let extras):
        FileHandle.standardError.write(
            Data(
                """
                error: unexpected argument(s) "\(extras.joined(separator: " "))" after shell-init. \
                Usage: vitrine shell-init [zsh|bash]

                """.utf8))
        exit(2)
    }
}

// Bring up the shared application as a background accessory: this initializes AppKit
// enough for `ImageRenderer`/Highlightr without showing a Dock icon or menu bar.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// Register the bundled monospaced fonts that ship next to the executable so the
// default font (JetBrains Mono) and every other bundled family render exactly as in
// the GUI. The `Fonts` directory is copied into the build output beside the binary.
CLIFontRegistration.registerBundledFonts(in: CLIEnvironment.bundledFontsDirectory)

/// Writes a line to standard error without buffering surprises.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

do {
    let options = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
    // PRO gate at the process boundary (CS-094): the CLI is direct-download only and
    // re-verifies the app's signed activation token itself. `--help` already exited
    // above (parse threw `helpRequested`), so a free build still sees usage but never
    // renders.
    guard CLIEntitlement.isProUnlocked() else { throw CLIError.proRequired }
    let summary: String
    switch options.command {
    case .render:
        // `--edit` hands the source to the running editor (no render); otherwise the
        // normal render-and-write/copy path produces the image.
        summary =
            options.openInEditor
            ? try CLIRenderer.openInEditor(options) : try CLIRenderer.run(options)
    case .batch: summary = try CLIRenderer.runBatch(options)
    }
    print(summary)
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
