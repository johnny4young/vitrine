import CryptoKit
import Foundation
import Testing

@testable import Vitrine

/// CS-094 — PRO gating for automation plus the folder `batch` command. Covers the
/// CLI's offline token verification (the acceptance "the CLI accepts only a
/// signature-valid token"), the `batch` parsing + directory loop, the clear
/// PRO-required error, and the guardrail that the local Debug bypass can never ship.
@MainActor
@Suite("CLI automation gating · CS-094")
struct CLIAutomationTests {
    // MARK: - Offline token verification (the CLI entitlement)

    @Test func aSignatureValidTokenUnlocksAndTamperingIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = LicenseVerifier(publicKey: key.publicKey)
        let token = try LicenseSigner.sign(
            LicenseToken(licenseID: "CLI-1", issuedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            with: key)

        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tokenURL = dir.appendingPathComponent("pro.token")
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)

        // A signature-valid token at the path unlocks, with no env bypass.
        #expect(
            CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: verifier, environment: [:]))

        // A tampered token is refused.
        try ("x." + token).write(to: tokenURL, atomically: true, encoding: .utf8)
        #expect(
            !CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: verifier, environment: [:]))

        // A token signed by a different key is refused by this verifier.
        try token.write(to: tokenURL, atomically: true, encoding: .utf8)
        let otherVerifier = LicenseVerifier(publicKey: Curve25519.Signing.PrivateKey().publicKey)
        #expect(
            !CLIEntitlement.isProUnlocked(
                tokenURL: tokenURL, verifier: otherVerifier, environment: [:]))
    }

    @Test func aMissingTokenIsLocked() {
        let url = tempDirectory().appendingPathComponent("absent.token")
        #expect(!CLIEntitlement.isProUnlocked(tokenURL: url, environment: [:]))
    }

    #if DEBUG
        @Test func theDebugEnvBypassUnlocksLocally() {
            // VITRINE_PRO_UNLOCK=1 unlocks for local development even with no token —
            // Debug only, so a release CLI never has this path.
            let url = tempDirectory().appendingPathComponent("absent.token")
            #expect(
                CLIEntitlement.isProUnlocked(
                    tokenURL: url, environment: ["VITRINE_PRO_UNLOCK": "1"]))
        }
    #endif

    /// Guardrail: the env bypass must be inside `#if DEBUG` so a release CLI can only be
    /// unlocked by a signature-valid token (mirrors the `DebugUnlockProvider` guard).
    @Test func theEnvBypassIsCompiledOutOfRelease() throws {
        let source = try String(
            contentsOf: Self.repoFile("Vitrine", "CLI", "CLIEntitlement.swift"), encoding: .utf8)
        let lines = source.components(separatedBy: "\n")
        // Match the bypass *code* (the environment read), not the doc-comment mention
        // that precedes it — the comment carries no `#if` and would defeat the scan.
        let index = try #require(
            lines.firstIndex { $0.contains("environment[\"VITRINE_PRO_UNLOCK\"]") },
            "the env bypass should be present in the source")
        let nearestConditional = lines[..<index].last {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#if")
        }
        #expect(
            nearestConditional?.contains("#if DEBUG") == true,
            "the CLI env bypass must be inside #if DEBUG so it never ships")
    }

    // MARK: - Version metadata

    @Test func versionInvocationAcceptsTopLevelCommandsAndJson() {
        #expect(CLIVersion.invocation(for: ["--version"]) == .version(format: .text))
        #expect(CLIVersion.invocation(for: ["-v"]) == .version(format: .text))
        #expect(CLIVersion.invocation(for: ["version"]) == .version(format: .text))
        #expect(CLIVersion.invocation(for: ["version", "--json"]) == .version(format: .json))
        #expect(CLIVersion.invocation(for: ["--version", "--json"]) == .version(format: .json))
        #expect(CLIVersion.invocation(for: ["version", "--help"]) == .help)
        #expect(CLIVersion.invocation(for: ["version", "--bad"]) == .unknownFlag("--bad"))
        #expect(CLIVersion.invocation(for: ["version", "extra"]) == .extraArguments(["extra"]))
        #expect(CLIVersion.invocation(for: ["render"]) == nil)
    }

    @Test func versionOutputUsesBundleValuesAndFallbackConstants() throws {
        let output = CLIVersion.output(
            format: .text,
            infoDictionary: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "456"],
            executablePath: "/missing/vitrine-cli")
        #expect(output == "vitrine 1.2.3 (456)\n")

        let jsonData = Data(
            CLIVersion.output(
                format: .json,
                infoDictionary: [
                    "CFBundleShortVersionString": "1.2.3",
                    "CFBundleVersion": "456",
                ],
                executablePath: "/missing/vitrine-cli"
            ).utf8)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: jsonData) as? [String: String])
        #expect(decoded == ["build": "456", "product": "vitrine", "version": "1.2.3"])

        let fallback = CLIVersion.output(
            format: .text, infoDictionary: [:], executablePath: "/missing/vitrine-cli")
        #expect(fallback == "vitrine 0.20.0 (21)\n")
    }

    @Test func versionFallbackConstantsMatchProjectSettings() throws {
        let project = try String(contentsOf: Self.repoFile("project.yml"), encoding: .utf8)
        #expect(project.contains("MARKETING_VERSION: \"\(CLIVersion.fallbackMarketingVersion)\""))
        #expect(project.contains("CURRENT_PROJECT_VERSION: \"\(CLIVersion.fallbackBuildNumber)\""))
    }

    // MARK: - Catalog listing

    @Test func catalogListInvocationAcceptsTextJsonAndSingularAliases() {
        #expect(CLICatalog.invocation(for: ["all"]) == .listing(.all, format: .text))
        #expect(CLICatalog.invocation(for: ["all", "--json"]) == .listing(.all, format: .json))
        #expect(CLICatalog.invocation(for: ["themes"]) == .listing(.themes, format: .text))
        #expect(
            CLICatalog.invocation(for: ["theme", "--json"]) == .listing(.themes, format: .json))
        #expect(
            CLICatalog.invocation(for: ["--json", "language"])
                == .listing(.languages, format: .json))
        #expect(CLICatalog.invocation(for: ["preset"]) == .listing(.presets, format: .text))
        #expect(CLICatalog.invocation(for: ["font"]) == .listing(.fonts, format: .text))
        #expect(
            CLICatalog.invocation(for: ["backgrounds"])
                == .listing(.backgrounds, format: .text))
        #expect(CLICatalog.invocation(for: ["format"]) == .listing(.formats, format: .text))
        #expect(CLICatalog.invocation(for: ["profiles"]) == .listing(.profiles, format: .text))
        #expect(CLICatalog.invocation(for: []) == .help)
    }

    @Test func catalogListRejectsUnknownTargetsFlagsAndExtraArguments() {
        #expect(CLICatalog.invocation(for: ["colors"]) == .unknownCatalog("colors"))
        #expect(CLICatalog.invocation(for: ["themes", "--bad"]) == .unknownFlag("--bad"))
        #expect(
            CLICatalog.invocation(for: ["themes", "languages"]) == .extraArguments(["languages"]))
    }

    @Test func catalogListPrintsStableTextAndJsonFromTheModelCatalogs() throws {
        let themeText = CLICatalog.output(for: .themes, format: .text)
        #expect(themeText.contains("dracula\tDracula\n"))
        #expect(themeText.contains("one-dark\tOne Dark\n"))

        let presetText = CLICatalog.output(for: .presets, format: .text)
        #expect(presetText.contains("opengraph\tOpenGraph 1200×630\n"))
        #expect(presetText.contains("transparent-slide\tTransparent Slide\n"))

        let formatText = CLICatalog.output(for: .formats, format: .text)
        #expect(formatText == "png\tPNG\npdf\tPDF\nheic\tHEIC\n")

        let profileText = CLICatalog.output(for: .profiles, format: .text)
        #expect(profileText == "srgb\tsRGB\np3\tDisplay P3 (advanced)\n")

        let fontText = CLICatalog.output(for: .fonts, format: .text)
        #expect(fontText.contains("JetBrains Mono\tJetBrains Mono\n"))
        #expect(fontText.contains("Fira Code\tFira Code\n"))

        let backgroundText = CLICatalog.output(for: .backgrounds, format: .text)
        #expect(
            backgroundText
                == "aurora\tAurora\nocean\tOcean\nsunset\tSunset\nforest\tForest\nnight\tNight\ncarbon\tCarbon\n"
        )

        let data = Data(CLICatalog.output(for: .languages, format: .json).utf8)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(decoded.contains { $0["id"] == "swift" && $0["name"] == "Swift" })
        #expect(decoded.contains { $0["id"] == "terminal" && $0["name"] == "Terminal" })

        let profileData = Data(CLICatalog.output(for: .profiles, format: .json).utf8)
        let profiles = try #require(
            JSONSerialization.jsonObject(with: profileData) as? [[String: String]])
        #expect(profiles.contains { $0["id"] == "srgb" && $0["name"] == "sRGB" })
        #expect(profiles.contains { $0["id"] == "p3" && $0["name"] == "Display P3 (advanced)" })
    }

    @Test func catalogListAllPrintsEveryCatalogAsTextAndJson() throws {
        let allText = CLICatalog.output(for: .all, format: .text)
        #expect(allText.contains("themes:\n"))
        #expect(allText.contains("  one-dark\tOne Dark\n"))
        #expect(allText.contains("languages:\n"))
        #expect(allText.contains("  swift\tSwift\n"))
        #expect(allText.contains("fonts:\n  JetBrains Mono\tJetBrains Mono\n"))
        #expect(allText.contains("backgrounds:\n  aurora\tAurora\n"))
        #expect(allText.contains("formats:\n  png\tPNG\n"))
        #expect(allText.contains("profiles:\n  srgb\tsRGB\n"))

        let data = Data(CLICatalog.output(for: .all, format: .json).utf8)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let themes = try #require(decoded["themes"] as? [[String: String]])
        let languages = try #require(decoded["languages"] as? [[String: String]])
        let presets = try #require(decoded["presets"] as? [[String: String]])
        let fonts = try #require(decoded["fonts"] as? [[String: String]])
        let backgrounds = try #require(decoded["backgrounds"] as? [[String: String]])
        let formats = try #require(decoded["formats"] as? [[String: String]])
        let profiles = try #require(decoded["profiles"] as? [[String: String]])
        #expect(themes.contains { $0["id"] == "one-dark" })
        #expect(languages.contains { $0["id"] == "swift" })
        #expect(presets.contains { $0["id"] == "opengraph" })
        #expect(fonts.contains { $0["id"] == "Fira Code" && $0["name"] == "Fira Code" })
        #expect(backgrounds.contains { $0["id"] == "aurora" && $0["name"] == "Aurora" })
        #expect(formats.contains { $0["id"] == "png" })
        #expect(profiles.contains { $0["id"] == "p3" })
    }

    @Test func parsesTheBatchCommandAndItsStyleFlags() throws {
        let options = try CLIArguments.parse(
            [
                "batch", "in-dir", "--out", "out-dir", "--quiet", "--theme", "dracula",
                "--font", "Hack", "--font-ligatures", "--corner-radius", "14",
                "--shadow-radius", "22", "--highlight-lines", "3, 7-9", "--focus-lines",
                "--redact-lines", "4-5", "--redact-secrets", "--diff-bands", "--recursive",
                "--fail-on-skipped", "--skipped-report", "skipped.json", "--dry-run", "--manifest",
                "manifest.json", "--include-ext", ".swift,md", "--exclude-ext", "tmp",
                "--fail-on-empty", "--no-overwrite",
            ])
        #expect(options.command == .batch)
        #expect(options.quiet)
        #expect(options.inputPath == "in-dir")
        #expect(options.outputPath == "out-dir")
        #expect(options.themeID == "dracula")
        #expect(options.recursiveBatch)
        #expect(options.failOnSkipped)
        #expect(options.skippedReportPath == "skipped.json")
        #expect(options.batchManifestPath == "manifest.json")
        #expect(options.dryRunBatch)
        #expect(options.batchIncludeExtensions == Set(["swift", "md"]))
        #expect(options.batchExcludeExtensions == Set(["tmp"]))
        #expect(options.fontName == "Hack")
        #expect(options.fontLigatures == true)
        #expect(options.cornerRadius == 14)
        #expect(options.shadowRadius == 22)
        #expect(options.highlightedLineRanges == [3...3, 7...9])
        #expect(options.redactedLineRanges == [4...5])
        #expect(options.redactSecrets)
        #expect(options.focusHighlightedLines == true)
        #expect(options.diffDecorations == true)
        #expect(options.failOnEmpty)
        #expect(options.noOverwrite)
        #expect(!options.jsonOutput)
    }

    @Test func recursiveIsBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --recursive.")) {
            try CLIArguments.parse(["render", "in.swift", "--out", "out.png", "--recursive"])
        }
    }

    @Test func failOnSkippedIsBatchOnly() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine render with --fail-on-skipped.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--fail-on-skipped",
            ])
        }
    }

    @Test func failOnEmptyIsBatchOnly() {
        #expect(
            throws: CLIError.incompatibleOptions(
                "Cannot combine render with --fail-on-empty.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--fail-on-empty",
            ])
        }
    }

    @Test func skippedReportIsBatchOnly() {
        #expect(
            throws: CLIError.incompatibleOptions("Cannot combine render with --skipped-report.")
        ) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--skipped-report", "skipped.json",
            ])
        }
    }

    @Test func manifestIsBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --manifest.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--manifest", "manifest.json",
            ])
        }
    }

    @Test func quietParsesForRenderAndBatch() throws {
        let render = try CLIArguments.parse([
            "render", "in.swift", "--out", "out.png", "--quiet",
        ])
        #expect(render.quiet)

        let batch = try CLIArguments.parse([
            "batch", "in-dir", "--out", "out-dir", "-q",
        ])
        #expect(batch.quiet)
    }

    @Test func dryRunIsBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --dry-run.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--dry-run",
            ])
        }
    }

    @Test func batchExtensionFiltersAreBatchOnly() {
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --include-ext.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--include-ext", "swift",
            ])
        }
        #expect(throws: CLIError.incompatibleOptions("Cannot combine render with --exclude-ext.")) {
            try CLIArguments.parse([
                "render", "in.swift", "--out", "out.png", "--exclude-ext", "tmp",
            ])
        }
    }

    @Test func batchExtensionFiltersRejectInvalidValues() {
        #expect(throws: CLIError.invalidValue(flag: "--include-ext", value: ",")) {
            try CLIArguments.parse([
                "batch", "in-dir", "--out", "out-dir", "--include-ext", ",",
            ])
        }
        #expect(throws: CLIError.invalidValue(flag: "--exclude-ext", value: "swift/evil")) {
            try CLIArguments.parse([
                "batch", "in-dir", "--out", "out-dir", "--exclude-ext", "swift/evil",
            ])
        }
    }

    @Test func batchRendersEveryTextFileInTheFolder() throws {
        let input = tempDirectory()
        let output = tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }
        try "let a = 1".write(
            to: input.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "x = 1\n".write(
            to: input.appendingPathComponent("b.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse(["batch", input.path, "--out", output.path])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 2 image"))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("A.png").path))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("b.png").path))
    }

    @Test func batchCanRenderNestedFoldersRecursively() throws {
        let input = tempDirectory()
        let output = tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
        }

        let docs = input.appendingPathComponent("docs", isDirectory: true)
        let scripts = input.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try "let title = \"Docs\"".write(
            to: docs.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        try "print('script')\n".write(
            to: scripts.appendingPathComponent("Sample.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--recursive", "--sidecars", "text",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 2 image"))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Sample.png").path))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Sample.txt").path))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("scripts/Sample.png").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: output.appendingPathComponent("Sample.png").path))
    }

    @Test func batchDryRunDoesNotWriteImagesOrSidecars() throws {
        let root = tempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path,
            "--dry-run",
            "--sidecars", "text",
            "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Dry run: would render 1 image"))
        #expect(summary.contains("skipped 1"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: String]])
        #expect(decoded == [["path": "Blob.bin", "reason": "not readable text"]])
    }

    @Test func batchManifestListsRenderedOutputsWithRelativePathsAndDimensions() throws {
        let input = tempDirectory()
        let output = tempDirectory()
        let manifest = tempDirectory().appendingPathComponent("manifest.json")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent())
        }
        let docs = input.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try "let ok = true\n".write(
            to: docs.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--recursive", "--manifest", manifest.path,
            "--sidecars", "text,html",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Ok.txt").path))
        #expect(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("docs/Ok.html").path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]])
        let entry = try #require(decoded.first)
        #expect(entry["input"] as? String == "docs/Ok.swift")
        #expect(entry["output"] as? String == "docs/Ok.png")
        #expect(entry["sidecars"] as? [String] == ["docs/Ok.txt", "docs/Ok.html"])
        #expect(entry["language"] as? String == "swift")
        #expect(entry["format"] as? String == "png")
        #expect(entry["status"] as? String == "rendered")
        #expect((entry["width"] as? Int ?? 0) > 0)
        #expect((entry["height"] as? Int ?? 0) > 0)
    }

    @Test func batchJsonSummaryReportsRenderedAndSkippedCounts() throws {
        let root = tempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--json", "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(summary.utf8)) as? [String: Any])
        #expect(decoded["command"] as? String == "batch")
        #expect(decoded["status"] as? String == "rendered")
        #expect(decoded["outputDirectory"] as? String == output.path)
        #expect(decoded["rendered"] as? Int == 1)
        #expect(decoded["skipped"] as? Int == 1)
        #expect(decoded["dryRun"] as? Bool == false)
        #expect(decoded["skippedReport"] as? String == report.path)
        #expect(decoded["manifest"] == nil)
    }

    @Test func batchDryRunManifestListsPlannedOutputsWithoutWritingImages() throws {
        let root = tempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "print('planned')\n".write(
            to: input.appendingPathComponent("Planned.py"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", "--manifest", manifest.path,
            "--text-sidecar",
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Dry run: would render 1 image"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]])
        let entry = try #require(decoded.first)
        #expect(entry["input"] as? String == "Planned.py")
        #expect(entry["output"] as? String == "Planned.png")
        #expect(entry["sidecars"] as? [String] == ["Planned.txt"])
        #expect(entry["language"] as? String == "python")
        #expect(entry["status"] as? String == "planned")
        #expect(entry["width"] == nil)
        #expect(entry["height"] == nil)
    }

    @Test func batchManifestDisambiguatesSameStemOutputs() throws {
        let root = tempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let value = 1\n".write(
            to: input.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        try "export const value = 1\n".write(
            to: input.appendingPathComponent("Widget.ts"), atomically: true, encoding: .utf8)
        try "print('solo')\n".write(
            to: input.appendingPathComponent("Solo.py"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Solo.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", "--manifest", manifest.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Dry run: would render 3 images"))
        #expect(summary.contains("skipped 1"))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]])
        let outputs = decoded.reduce(into: [String: String]()) { result, entry in
            if let input = entry["input"] as? String, let output = entry["output"] as? String {
                result[input] = output
            }
        }
        #expect(outputs["Solo.py"] == "Solo.png")
        #expect(outputs["Widget.swift"] == "Widget.swift.png")
        #expect(outputs["Widget.ts"] == "Widget.ts.png")
    }

    @Test func batchNoOverwriteSkipsExistingTargetsAndReportsThem() throws {
        let root = tempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try "let old = true\n".write(
            to: input.appendingPathComponent("Old.swift"), atomically: true, encoding: .utf8)
        try "print('fresh')\n".write(
            to: input.appendingPathComponent("Fresh.py"), atomically: true, encoding: .utf8)
        let existing = output.appendingPathComponent("Old.png")
        try Data("existing image".utf8).write(to: existing)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--no-overwrite",
            "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(summary.contains("skipped 1"))
        #expect(try Data(contentsOf: existing) == Data("existing image".utf8))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Fresh.png").path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: String]])
        #expect(decoded == [["path": "Old.swift", "reason": "output already exists"]])
    }

    @Test func batchFailOnEmptyFailsAfterWritingRequestedArtifacts() throws {
        let root = tempDirectory()
        let input = root.appendingPathComponent("input", isDirectory: true)
        let output = root.appendingPathComponent("out", isDirectory: true)
        let manifest = root.appendingPathComponent("manifest.json")
        let report = root.appendingPathComponent("skipped.json")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try "let ignored = true\n".write(
            to: input.appendingPathComponent("Ignored.swift"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--dry-run", "--include-ext", "go",
            "--fail-on-empty", "--manifest", manifest.path, "--skipped-report", report.path,
        ])

        #expect(throws: CLIError.batchEmpty(skipped: 0)) {
            try CLIRenderer.runBatch(options)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try String(contentsOf: manifest, encoding: .utf8) == "[]\n")
        #expect(try String(contentsOf: report, encoding: .utf8) == "[]\n")
    }

    @Test func batchExtensionFiltersAreAppliedBeforeLoading() throws {
        let input = tempDirectory()
        let output = tempDirectory()
        let report = tempDirectory().appendingPathComponent("skipped.json")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: report.deletingLastPathComponent())
        }
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try "# Notes\n".write(
            to: input.appendingPathComponent("Guide.md"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))
        try "plain text".write(
            to: input.appendingPathComponent("README"), atomically: true, encoding: .utf8)

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path,
            "--include-ext", ".swift,md",
            "--exclude-ext", "md",
            "--skipped-report", report.path,
        ])
        let summary = try CLIRenderer.runBatch(options)

        #expect(summary.contains("Rendered 1 image"))
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Ok.png").path))
        #expect(
            !FileManager.default.fileExists(atPath: output.appendingPathComponent("Guide.png").path)
        )
        #expect(
            !FileManager.default.fileExists(atPath: output.appendingPathComponent("Blob.png").path))
        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: String]])
        #expect(decoded.isEmpty)
    }

    @Test func batchCanFailWhenAnyFileIsSkippedAndStillWritesASkippedReport() throws {
        let input = tempDirectory()
        let output = tempDirectory()
        let report = tempDirectory().appendingPathComponent("skipped.json")
        defer {
            try? FileManager.default.removeItem(at: input)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: report.deletingLastPathComponent())
        }
        try "let ok = true\n".write(
            to: input.appendingPathComponent("Ok.swift"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01, 0x02]).write(to: input.appendingPathComponent("Blob.bin"))

        let options = try CLIArguments.parse([
            "batch", input.path, "--out", output.path, "--fail-on-skipped",
            "--skipped-report", report.path,
        ])

        #expect(throws: CLIError.batchSkipped(rendered: 1, skipped: 1)) {
            try CLIRenderer.runBatch(options)
        }
        #expect(
            FileManager.default.fileExists(atPath: output.appendingPathComponent("Ok.png").path))
        let data = try Data(contentsOf: report)
        let decoded = try #require(
            JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(decoded == [["path": "Blob.bin", "reason": "not readable text"]])
    }

    @Test func batchEmptyReportsAClearMessageAndFailureExitCode() {
        #expect(CLIError.batchEmpty(skipped: 0).message == "Batch found no renderable input files.")
        #expect(
            CLIError.batchEmpty(skipped: 2).message
                == "Batch found no renderable input files (skipped 2 files).")
        #expect(CLIError.batchEmpty(skipped: 0).exitCode == 1)
    }

    @Test func proRequiredReportsAClearMessageAndFailureExitCode() {
        #expect(!CLIError.proRequired.message.isEmpty)
        #expect(CLIError.proRequired.exitCode == 1)
    }

    // MARK: - Helpers

    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCLIAuto-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func repoFile(_ components: String...) -> URL {
        components.reduce(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // Tests/
                .deletingLastPathComponent()  // repo root
        ) { $0.appendingPathComponent($1) }
    }
}
