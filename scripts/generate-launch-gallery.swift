#!/usr/bin/env swift  // Generate the launch-gallery design-QA artifacts.
//
// A screenshot app should ship with evidence of its visual quality. This script is
// the single command that (re)generates the representative code-screenshot samples
// used in the README/release notes and committed under Tests/Fixtures/Samples/, all
// rendered through the app's real export pipeline — never hand-made mockups.
//
// How it works (the same staging dance as scripts/record-goldens.sh): the
// unit-test host is sandboxed and cannot write into the source tree, so the
// generator suite (`SampleGalleryGeneratorTests`, armed by VITRINE_GENERATE_GALLERY)
// renders every catalog sample, stages the PNGs and manifest.json in its own
// container temp, and prints the (sandbox-remapped) path on one `GALLERY OUTPUT
// <path>` line. This script drives that suite via xcodebuild, parses the staging
// path, and copies the staged files into Tests/Fixtures/Samples/ from outside the
// sandbox.
//
// It is written in Swift (not bash) to match the documented file and
// the repo's other standalone tool, scripts/compare-goldens.swift. It depends on
// nothing but Foundation and shells out to the same `xcodebuild` the Makefile uses,
// so `swift scripts/generate-launch-gallery.swift` (or `make gallery`) needs no build
// step of its own.
//
// Run it when a deliberate visual change lands, then review and commit the diff.
//
// Exit codes: 0 = generated and copied, 1 = build/parse/copy failure, 2 = tooling
// (xcodebuild) not found.

import Foundation

/// Writes a line to standard error.
func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// The repository root, derived from this script's own location
/// (`<repo>/scripts/generate-launch-gallery.swift`).
let repoRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let project = ProcessInfo.processInfo.environment["PROJECT"] ?? "Vitrine.xcodeproj"
let scheme = ProcessInfo.processInfo.environment["SCHEME"] ?? "Vitrine"
let destinationDirectory =
    repoRoot
    .appendingPathComponent("Tests/Fixtures/Samples", isDirectory: true)

/// Resolves the developer dir the Makefile uses: a full Xcode if present (even when
/// `xcode-select` points at the Command Line Tools), else whatever `DEVELOPER_DIR`
/// already names. xcodebuild needs full Xcode; mirroring the Makefile keeps this
/// script working in the same setups.
func developerDirectory() -> String? {
    if let explicit = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !explicit.isEmpty {
        return explicit
    }
    let xcodeDeveloper = "/Applications/Xcode.app/Contents/Developer"
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: xcodeDeveloper, isDirectory: &isDir), isDir.boolValue
    {
        return xcodeDeveloper
    }
    return nil
}

/// Runs `xcodebuild` to drive the opt-in gallery generator suite, capturing its
/// combined output so the `GALLERY OUTPUT` staging line can be parsed. The output is
/// also echoed live so the run is observable.
func runGenerator() -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var arguments = ["xcodebuild"]
    arguments += ["-project", repoRoot.appendingPathComponent(project).path]
    arguments += ["-scheme", scheme]
    arguments += ["-configuration", "Debug"]
    arguments += ["-destination", "platform=macOS"]
    arguments += ["-only-testing:VitrineTests/SampleGalleryGeneratorTests"]
    // Forwarded into the test runner via the scheme's $(VITRINE_GENERATE_GALLERY)
    // macro; an exported shell var alone is not passed to the test process.
    arguments += ["VITRINE_GENERATE_GALLERY=1", "test"]
    process.arguments = arguments

    var environment = ProcessInfo.processInfo.environment
    if let developerDir = developerDirectory() {
        environment["DEVELOPER_DIR"] = developerDir
    }
    process.environment = environment

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    var collected = Data()
    let handle = pipe.fileHandleForReading
    handle.readabilityHandler = { fileHandle in
        let chunk = fileHandle.availableData
        guard !chunk.isEmpty else { return }
        collected.append(chunk)
        FileHandle.standardOutput.write(chunk)
    }

    do {
        try process.run()
    } catch {
        warn("error: could not launch xcodebuild — is full Xcode installed? (\(error))")
        return (2, "")
    }
    process.waitUntilExit()
    handle.readabilityHandler = nil
    // Drain anything buffered after the last readability callback.
    let remainder = handle.readDataToEndOfFile()
    if !remainder.isEmpty {
        collected.append(remainder)
        FileHandle.standardOutput.write(remainder)
    }
    return (process.terminationStatus, String(decoding: collected, as: UTF8.self))
}

/// Extracts the single `GALLERY OUTPUT <abs path>` line the generator prints.
func stagingPath(from output: String) -> String? {
    for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
        guard let range = line.range(of: "GALLERY OUTPUT ") else { continue }
        let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        if !path.isEmpty { return path }
    }
    return nil
}

/// Copies every staged PNG plus the manifest into the committed fixtures directory,
/// overwriting any existing file so a re-generate produces a clean diff. Returns the
/// number of PNGs copied.
func copyArtifacts(from staging: String) throws -> Int {
    let fileManager = FileManager.default
    let stagingURL = URL(fileURLWithPath: staging, isDirectory: true)
    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

    let entries = try fileManager.contentsOfDirectory(
        at: stagingURL, includingPropertiesForKeys: nil)
    var copiedPNGs = 0
    for source in entries {
        let isPNG = source.pathExtension.lowercased() == "png"
        let isManifest = source.lastPathComponent == "manifest.json"
        guard isPNG || isManifest else { continue }
        let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        if isPNG { copiedPNGs += 1 }
    }
    return copiedPNGs
}

// MARK: - Run

print("Generating launch-gallery samples (this renders every sample through the export path)…")

guard developerDirectory() != nil else {
    warn(
        "error: full Xcode not found (xcodebuild requires it). Install Xcode or set DEVELOPER_DIR.")
    exit(2)
}

let result = runGenerator()
guard result.status == 0 else {
    warn("error: the gallery generator suite failed (xcodebuild exit \(result.status)).")
    exit(result.status == 2 ? 2 : 1)
}

guard let staging = stagingPath(from: result.output) else {
    warn("error: could not locate the generator staging directory (no GALLERY OUTPUT line).")
    exit(1)
}

do {
    let count = try copyArtifacts(from: staging)
    print("Copied \(count) sample images + manifest into \(destinationDirectory.path)")
    print("Review the diff and commit it.")
} catch {
    warn("error: failed to copy generated artifacts: \(error)")
    exit(1)
}
