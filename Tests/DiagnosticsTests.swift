import Foundation
import Testing

@testable import Vitrine

// MARK: - Fixtures

extension DiagnosticsBundle.Environment {
    /// A fixed environment so bundle output is deterministic in tests.
    static let fixture = DiagnosticsBundle.Environment(
        product: "Vitrine",
        appVersion: "1.2.3",
        buildNumber: "42",
        osVersion: "macOS 14.5.0",
        architecture: "arm64"
    )
}

extension DiagnosticsSettingsSnapshot {
    /// A representative settings snapshot. Note it carries **no** code field by
    /// design — the type cannot hold user code.
    static let fixture = DiagnosticsSettingsSnapshot(
        themeID: "dracula",
        languageID: "swift",
        fontName: "JetBrains Mono",
        fontSize: 14,
        padding: 32,
        cornerRadius: 12,
        showChrome: true,
        showShadow: true,
        backgroundKind: "gradient(Aurora)",
        autoCopy: true,
        alsoSaveToFile: false,
        exportScale: 2,
        exportFormat: "png",
        colorProfile: "sRGB",
        hotkeyAction: "quickCapture",
        treatURLsAsScreenshot: false,
        recentLanguageCount: 3,
        schemaVersion: 2
    )
}

// MARK: - Redaction

@Suite("Diagnostics redaction")
struct DiagnosticsRedactionTests {
    /// The single most important guarantee (CS-048): a generated bundle never
    /// contains the code the user was editing, no matter what that code was.
    @Test func bundleNeverContainsUserCode() {
        // A deliberately distinctive secret that would be unmistakable if it leaked.
        let secret = "SUPER_SECRET_TOKEN_d3adb33f_let_x_=_42"
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DiagRedaction-\(UUID())")!)
        settings.config.code = """
            // \(secret)
            func leak() { print("\(secret)") }
            """

        let bundle = DiagnosticsBundle.build(
            environment: .fixture, settings: settings.diagnosticsSnapshot)
        let text = bundle.text(generatedAt: Date(timeIntervalSince1970: 0))

        #expect(!text.contains(secret))
        #expect(!text.contains("func leak"))
        // The snapshot itself must not carry the code through any field.
        for line in bundle.settings {
            #expect(!line.value.contains(secret))
        }
    }

    /// A solid background color is reported only as "solid", never as an RGBA the
    /// user picked, so even a chosen color does not leak as identifying data.
    @Test func solidBackgroundIsReportedWithoutColorValue() {
        var config = SnapshotConfig()
        config.background = .solid(.red)
        #expect(config.background.diagnosticsKind == "solid")
    }

    /// A gradient background reports its built-in preset name and *only* that — the
    /// label is exactly `gradient(<presetRawValue>)`, never any color/RGBA. Asserts
    /// every preset so a future preset cannot silently widen what the label carries.
    @Test func gradientBackgroundReportsOnlyPresetName() {
        for preset in GradientPreset.allCases {
            var config = SnapshotConfig()
            config.background = .gradient(preset)
            #expect(config.background.diagnosticsKind == "gradient(\(preset.rawValue))")
            // The label exposes the preset's enum name, not any color component the
            // gradient is built from (e.g. a hex like "#2E3192").
            #expect(!config.background.diagnosticsKind.contains("#"))
        }
    }

    /// A transparent background reports the fixed label "transparent" — no value to
    /// leak, but pinned so the case stays covered alongside the others.
    @Test func transparentBackgroundIsReportedAsTransparent() {
        var config = SnapshotConfig()
        config.background = .transparent
        #expect(config.background.diagnosticsKind == "transparent")
    }

    /// The bundle promises "no file paths," yet a user might well have a path inside
    /// the code they are editing. Building from that settings state must still yield a
    /// bundle whose rendered text contains neither the path nor the code around it —
    /// the snapshot copies only behavioral knobs, so nothing free-form rides along.
    @Test func bundleNeverContainsAFilePathFromUserCode() {
        let path = "/Users/janedoe/Secret Project/credentials.env"
        let settings = AppSettings(defaults: UserDefaults(suiteName: "DiagPaths-\(UUID())")!)
        settings.config.code = """
            let key = loadKey(from: "\(path)")
            """

        let bundle = DiagnosticsBundle.build(
            environment: .fixture, settings: settings.diagnosticsSnapshot)
        let text = bundle.text(generatedAt: Date(timeIntervalSince1970: 0))

        #expect(!text.contains(path))
        #expect(!text.contains("/Users/janedoe"))
        #expect(!text.contains("credentials.env"))
        // And the rendered text still carries the self-describing privacy note that
        // makes the no-paths promise to the reader.
        #expect(text.contains(DiagnosticsBundle.privacyNote))
    }

    /// Recent languages are summarized as a count, never enumerated, so a user's
    /// language usage history is not reproduced verbatim.
    @Test func recentLanguagesAreReportedAsACountOnly() {
        let lines = DiagnosticsSettingsSnapshot.fixture.redactedLines()
        let countLine = lines.first { $0.key == "recentLanguageCount" }
        #expect(countLine?.value == "3")
        #expect(!lines.contains { $0.key == "recentLanguages" })
    }
}

// MARK: - Schema / reproducibility

@Suite("Diagnostics bundle schema")
struct DiagnosticsSchemaTests {
    @Test func bundleCarriesEnvironmentAndCategories() {
        let bundle = DiagnosticsBundle.build(
            environment: .fixture, settings: .fixture)

        #expect(bundle.product == "Vitrine")
        #expect(bundle.appVersion == "1.2.3")
        #expect(bundle.buildNumber == "42")
        #expect(bundle.osVersion == "macOS 14.5.0")
        #expect(bundle.architecture == "arm64")
        // Every Log category is documented in the bundle.
        #expect(bundle.logCategories == Log.Category.allCases.map(\.rawValue).sorted())
    }

    @Test func renderedTextDocumentsItsContents() {
        let bundle = DiagnosticsBundle.build(environment: .fixture, settings: .fixture)
        let text = bundle.text(generatedAt: Date(timeIntervalSince1970: 0))

        // Self-describing header and sections (CS-048: "documents exactly what it
        // contains").
        #expect(text.contains("# Vitrine diagnostics"))
        #expect(text.contains("schema: \(DiagnosticsBundle.schemaVersion)"))
        #expect(text.contains("## Environment"))
        #expect(text.contains("## Settings (user code redacted)"))
        #expect(text.contains("## Log categories"))
        #expect(text.contains("subsystem: \(Log.subsystem)"))
        #expect(text.contains("## Recent log (this session, non-PII)"))
        #expect(text.contains("## Privacy"))
        #expect(text.contains(DiagnosticsBundle.privacyNote))
        // Representative redacted values appear.
        #expect(text.contains("app version: 1.2.3 (42)"))
        #expect(text.contains("theme: dracula"))
    }

    @Test func recentLogSectionNotesWhenEmpty() {
        let bundle = DiagnosticsBundle.build(environment: .fixture, settings: .fixture)
        let text = bundle.text(generatedAt: Date(timeIntervalSince1970: 0))
        #expect(text.contains("## Recent log (this session, non-PII)\n(none captured)"))
    }

    @Test func recentLogExcerptsRenderWithLevelAndCategory() {
        let bundle = DiagnosticsBundle.build(
            environment: .fixture,
            settings: .fixture,
            logExcerpts: [
                .init(category: "capture", level: "info", message: "Quick capture complete"),
                .init(category: "export", level: "notice", message: "Saved image to file (png)"),
            ]
        )
        let text = bundle.text(generatedAt: Date(timeIntervalSince1970: 0))
        #expect(text.contains("[info] capture: Quick capture complete"))
        #expect(text.contains("[notice] export: Saved image to file (png)"))
    }

    @Test func renderedTextIsReproducibleForFixedInputs() {
        let bundle = DiagnosticsBundle.build(environment: .fixture, settings: .fixture)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        // Same inputs (including timestamp) yield byte-identical output.
        #expect(bundle.text(generatedAt: date) == bundle.text(generatedAt: date))
    }

    @Test func settingsLinesAreSortedByKey() {
        let lines = DiagnosticsSettingsSnapshot.fixture.redactedLines()
        let keys = lines.map(\.key)
        #expect(keys == keys.sorted())
    }

    @Test func settingsSnapshotIncludesCopyableTextSidecarKnob() {
        let defaults = UserDefaults(suiteName: "DiagTextSidecar-\(UUID())")!
        let settings = AppSettings(defaults: defaults)
        settings.textSidecar = true

        let lines = settings.diagnosticsSnapshot.redactedLines()
        let sidecarLine = lines.first { $0.key == "textSidecar" }
        #expect(sidecarLine?.value == "true")
    }
}

// MARK: - Source hygiene (the `print(` lint check)

@Suite("Logging hygiene")
struct LoggingHygieneTests {
    /// CS-048: shipping targets must contain no stray `print(` (or `NSLog`) — all
    /// diagnostics go through `os.Logger`. We scan the real `Vitrine/` source tree,
    /// ignoring occurrences that live *inside string literals* (e.g. sample code in
    /// the Style preview, or the language-detection heuristics), which are data, not
    /// logging statements.
    @Test func shippingSourcesUseLoggerNotPrint() throws {
        let sourceRoot = Self.shippingSourceRoot()
        let files = try Self.swiftFiles(in: sourceRoot)
        #expect(!files.isEmpty, "Expected to find Vitrine sources at \(sourceRoot.path)")

        var offenders: [String] = []
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, rawLine) in contents.split(
                separator: "\n", omittingEmptySubsequences: false
            ).enumerated() {
                let code = Self.strippingStringLiterals(from: String(rawLine))
                if code.contains("print(") || code.contains("NSLog(") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }

        #expect(offenders.isEmpty, "Stray print(/NSLog( in shipping code: \(offenders)")
    }

    /// The check is meaningful only if it can actually see a `print(` — verify the
    /// literal-stripping does not hide a real call.
    @Test func detectorFlagsARealPrintButNotOneInAString() {
        // A bare statement is flagged.
        #expect(Self.strippingStringLiterals(from: "    print(x)").contains("print("))
        // The same token inside a string literal is treated as data, not a call.
        #expect(!Self.strippingStringLiterals(from: #"let s = "print(x)""#).contains("print("))
        // Escaped quotes inside the literal do not end it early.
        #expect(
            !Self.strippingStringLiterals(from: #"let s = "a \"print(\" b""#).contains("print("))
    }

    // MARK: Helpers

    /// Locates the `Vitrine/` source directory relative to this test file, which
    /// lives in the sibling `Tests/` directory.
    private static func shippingSourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)  // .../Tests/DiagnosticsTests.swift
            .deletingLastPathComponent()  // .../Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Vitrine", isDirectory: true)
    }

    /// All `.swift` files under `root`, recursively.
    private static func swiftFiles(in root: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            result.append(url)
        }
        return result
    }

    /// Replaces the contents of double-quoted string literals on a single line with
    /// empty strings, so a search for `print(` on the result only matches real
    /// calls and not text inside a literal. Honors backslash escapes; it does not
    /// need to handle multi-line string literals because the known sample-code
    /// literals are single-line, and the check is intentionally conservative.
    static func strippingStringLiterals(from line: String) -> String {
        var output = ""
        var insideString = false
        var escaped = false
        for character in line {
            if insideString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    insideString = false
                }
                continue
            }
            if character == "\"" {
                insideString = true
                continue
            }
            output.append(character)
        }
        return output
    }
}
