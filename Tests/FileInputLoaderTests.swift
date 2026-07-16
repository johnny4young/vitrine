import Foundation
import Testing

@testable import Vitrine

/// CS-028 — drag-and-drop / file input loading.
///
/// These suites exercise `FileInputLoader`: the pure `decode(data:filename:)`
/// policy (size cap, binary rejection, text decoding, language inference) driven
/// from in-memory fixtures, plus the thin `load(from:)` wrapper driven from real
/// temporary files so the security-scoped read path is covered end to end.

/// Writes `data` to a unique temporary file with `name`, returning its URL. The
/// file is created fresh per call so tests never collide.
private func temporaryFile(named name: String, data: Data) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VitrineCS028-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name, isDirectory: false)
    try data.write(to: url)
    return url
}

// MARK: - Pure decoding from fixtures

@Suite("FileInputLoader.decode")
struct FileInputLoaderDecodeTests {
    /// A text file loads its contents verbatim and infers the language from the
    /// extension (the primary acceptance: "loads text and infers language by
    /// extension").
    @Test func textFileLoadsAndInfersLanguageByExtension() throws {
        let source = "import SwiftUI\n\nstruct A {}\n"
        let loaded = try FileInputLoader.decode(
            data: Data(source.utf8), filename: "ContentView.swift")
        #expect(loaded.text == source)
        #expect(loaded.language == .swift)
        #expect(loaded.filename == "ContentView.swift")
    }

    /// The extension wins even when the content would score as another language:
    /// a `.py` file full of SQL-looking text still loads as Python.
    @Test func extensionTakesPrecedenceOverContent() throws {
        let loaded = try FileInputLoader.decode(
            data: Data("SELECT * FROM users WHERE id = 1\n".utf8), filename: "query.py")
        #expect(loaded.language == .python)
    }

    /// An unknown extension falls back to weighted content detection.
    @Test func unknownExtensionFallsBackToContentDetection() throws {
        let go = "package main\n\nfunc main() {\n\tfmt.Println(\"hi\")\n}\n"
        let loaded = try FileInputLoader.decode(data: Data(go.utf8), filename: "snippet.unknownext")
        #expect(loaded.language == .go)
    }

    /// A file with no extension at all also falls back to content detection.
    @Test func extensionlessFileUsesContentDetection() throws {
        let loaded = try FileInputLoader.decode(
            data: Data("def greet():\n    pass\n".utf8), filename: "notes")
        #expect(loaded.language == .python)
    }

    /// The well-known extensionless `Dockerfile` is recognized by name (it has no
    /// extension, so this confirms the path-based inference handles it).
    @Test func dockerfileIsRecognizedByName() throws {
        let loaded = try FileInputLoader.decode(
            data: Data("FROM swift:latest\nRUN swift build\n".utf8), filename: "Dockerfile")
        #expect(loaded.language == .dockerfile)
    }

    /// A binary file — detected by an embedded NUL byte — is rejected with the
    /// binary error (acceptance: "Binary files are rejected with a clear message").
    @Test func binaryFileWithNulByteIsRejected() {
        var bytes: [UInt8] = Array("PK".utf8)  // ZIP-like header
        bytes.append(contentsOf: [0x03, 0x04, 0x00, 0xFF, 0x00, 0x10])
        #expect(throws: FileInputLoader.LoadError.binaryFile) {
            _ = try FileInputLoader.decode(data: Data(bytes), filename: "archive.zip")
        }
    }

    /// Even with a source-code extension, binary bytes are rejected: detection is
    /// content-based, never the extension alone.
    @Test func binaryBytesAreRejectedRegardlessOfExtension() {
        let bytes = Data([0x00, 0x01, 0x02, 0x03, 0x00, 0xFE])
        #expect(throws: FileInputLoader.LoadError.binaryFile) {
            _ = try FileInputLoader.decode(data: bytes, filename: "looks.swift")
        }
    }

    /// A file at the exact size cap still loads; one byte over is refused.
    @Test func sizeCapIsEnforced() throws {
        let atLimit = Data(repeating: UInt8(ascii: "a"), count: FileInputLoader.maximumByteCount)
        let loaded = try FileInputLoader.decode(data: atLimit, filename: "big.txt")
        #expect(loaded.text.count == FileInputLoader.maximumByteCount)

        let overLimit = Data(
            repeating: UInt8(ascii: "a"), count: FileInputLoader.maximumByteCount + 1)
        #expect(throws: FileInputLoader.LoadError.tooLarge) {
            _ = try FileInputLoader.decode(data: overLimit, filename: "huge.txt")
        }
    }

    /// An empty file is valid text and loads as an empty document, not a binary
    /// rejection.
    @Test func emptyFileLoadsAsEmptyText() throws {
        let loaded = try FileInputLoader.decode(data: Data(), filename: "empty.txt")
        #expect(loaded.text.isEmpty)
        #expect(loaded.language == .plaintext)
    }

    /// Non-UTF-8 encodings still decode through the fallback list rather than being
    /// misclassified as binary. Latin-1 bytes that are invalid UTF-8 round-trip.
    @Test func latin1FileDecodesThroughFallback() throws {
        // 0xE9 is "é" in ISO-8859-1 but an invalid lone UTF-8 lead byte.
        let bytes = Data([UInt8(ascii: "c"), UInt8(ascii: "a"), UInt8(ascii: "f"), 0xE9])
        let loaded = try FileInputLoader.decode(data: bytes, filename: "cafe.txt")
        #expect(loaded.text.contains("caf"))
    }
}

// MARK: - Binary detection helper

@Suite("FileInputLoader.decodeText")
struct FileInputLoaderDecodeTextTests {
    @Test func plainAsciiDecodes() {
        #expect(FileInputLoader.decodeText(from: Data("hello".utf8)) == "hello")
    }

    @Test func nulByteIsBinary() {
        #expect(FileInputLoader.decodeText(from: Data([0x68, 0x00, 0x69])) == nil)
    }

    @Test func emptyDataIsEmptyText() {
        #expect(FileInputLoader.decodeText(from: Data()) == "")
    }

    @Test func utf8MultibyteDecodes() {
        let text = "let π = 3.14 // 日本語"
        #expect(FileInputLoader.decodeText(from: Data(text.utf8)) == text)
    }

    /// UTF-16 text carries NUL bytes (ASCII high bytes), so it must be recognized
    /// by its BOM and not rejected by the NUL-based binary heuristic.
    @Test func utf16WithBOMDecodesDespiteNulBytes() {
        let text = "let x = 1"
        let data = text.data(using: .utf16)!  // Foundation prepends a BOM.
        #expect(data.contains(0))  // precondition: it really has NUL bytes
        #expect(FileInputLoader.decodeText(from: data) == text)
    }

    /// A UTF-8 BOM (common from Windows editors) must be stripped: decoding the
    /// raw bytes as `.utf8` keeps the U+FEFF, and the invisible scalar would leak
    /// into the editor, language detection, and sidecar text.
    @Test func utf8BOMIsStripped() {
        let text = "let x = 1"
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        #expect(FileInputLoader.decodeText(from: data) == text)
    }
}

// MARK: - Language inference

@Suite("FileInputLoader.inferLanguage")
struct FileInputLoaderInferLanguageTests {
    @Test(arguments: [
        ("main.swift", Language.swift),
        ("app.tsx", .typescript),
        ("My Component.tsx", .typescript),
        ("~/Snippets/My View.swift", .swift),
        ("script.mjs", .javascript),
        ("style.scss", .scss),
        ("config.yml", .yaml),
        ("changes.diff", .diff),
        ("changes.patch", .diff),
        ("Dockerfile", .dockerfile),
    ])
    func extensionMapsToLanguage(filename: String, expected: Language) {
        #expect(FileInputLoader.inferLanguage(forFilename: filename, content: "") == expected)
    }

    @Test func unknownExtensionScoresContent() {
        let swift = "import Foundation\nfunc f() -> some View { Text(\"x\") }"
        #expect(FileInputLoader.inferLanguage(forFilename: "x.bin", content: swift) == .swift)
    }

    @Test func ansiContentIsTerminalEvenWithAPlainExtension() {
        // A `.txt`/`.log` of colored output is terminal — the ANSI escapes override
        // the extension, which would otherwise infer plain text.
        let output = "\u{1B}[31merror:\u{1B}[0m build failed"
        #expect(
            FileInputLoader.inferLanguage(forFilename: "build.log", content: output) == .terminal)
        #expect(FileInputLoader.inferLanguage(forFilename: "out.txt", content: output) == .terminal)
    }
}

// MARK: - File loading from disk (security-scoped path)

@Suite("FileInputLoader.load")
struct FileInputLoaderLoadTests {
    /// Loading a real text file reads its bytes and infers the language, exercising
    /// the `startAccessingSecurityScopedResource` bracket end to end.
    @Test func loadsTextFileFromDisk() throws {
        let source = "interface User { id: number }\n"
        let url = try temporaryFile(named: "model.ts", data: Data(source.utf8))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let loaded = try FileInputLoader.load(from: url)
        #expect(loaded.text == source)
        #expect(loaded.language == .typescript)
        #expect(loaded.filename == "model.ts")
    }

    /// A real binary file on disk is rejected with the binary error.
    @Test func rejectsBinaryFileFromDisk() throws {
        let url = try temporaryFile(
            named: "image.png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x1A, 0x0A]))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: FileInputLoader.LoadError.binaryFile) {
            _ = try FileInputLoader.load(from: url)
        }
    }

    /// A URL that does not point at any file surfaces the unreadable error rather
    /// than trapping.
    @Test func missingFileIsUnreadable() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineCS028-missing-\(UUID().uuidString).swift")
        #expect(throws: FileInputLoader.LoadError.unreadable) {
            _ = try FileInputLoader.load(from: url)
        }
    }
}

// MARK: - Applying a drop into the config (replace / append / metadata)

@Suite("FileInputLoader.LoadedFile.apply")
struct FileInputLoaderApplyTests {
    /// Replacing an empty editor swaps in the text, adopts the inferred language,
    /// and records the source filename in `metadata.filename` so a *later*
    /// capture/export reflects where the code came from — the model side of
    /// "Recents record loaded file metadata only when the user captures/exports".
    @Test func replaceAdoptsTextLanguageAndFilename() {
        var config = SnapshotConfig(code: "", language: .plaintext)
        let loaded = FileInputLoader.LoadedFile(
            text: "interface User { id: number }\n", language: .typescript, filename: "model.ts")

        loaded.apply(to: &config, replacing: true)

        #expect(config.code == "interface User { id: number }\n")
        #expect(config.language == .typescript)
        #expect(config.metadata.filename == "model.ts")
    }

    /// Replacing existing code discards the whole prior document (it is the
    /// destructive choice), not merely prepends to it.
    @Test func replaceDiscardsExistingDocument() {
        var config = SnapshotConfig(code: "OLD CONTENT\nsecond line\n", language: .swift)
        let loaded = FileInputLoader.LoadedFile(
            text: "print('new')\n", language: .python, filename: "new.py")

        loaded.apply(to: &config, replacing: true)

        #expect(config.code == "print('new')\n")
        #expect(!config.code.contains("OLD CONTENT"))
        #expect(config.language == .python)
    }

    /// Replacing the document is a new capture, so content-bound marks (annotations,
    /// highlighted lines) positioned over the old code are dropped.
    @Test func replaceClearsContentBoundMarks() {
        var config = SnapshotConfig(code: "OLD\n", language: .swift)
        config.annotations = [Annotation(kind: .text, start: .zero, end: .zero)]
        config.highlightedLineRanges = [1...2]
        let loaded = FileInputLoader.LoadedFile(
            text: "print('new')\n", language: .python, filename: "new.py")

        loaded.apply(to: &config, replacing: true)

        #expect(config.annotations.isEmpty)
        #expect(config.highlightedLineRanges.isEmpty)
    }

    /// Appending grows the *same* document, so its marks are kept.
    @Test func appendKeepsContentBoundMarks() {
        var config = SnapshotConfig(code: "let a = 1\n", language: .swift)
        config.annotations = [Annotation(kind: .text, start: .zero, end: .zero)]
        config.highlightedLineRanges = [1...1]
        let loaded = FileInputLoader.LoadedFile(
            text: "let b = 2\n", language: .swift, filename: "more.swift")

        loaded.apply(to: &config, replacing: false)

        #expect(config.annotations.count == 1)
        #expect(config.highlightedLineRanges == [1...1])
    }

    /// A dropped *text* payload carries no filename, so replacing must not stamp an
    /// empty filename onto the metadata (which would reserve an empty header chip).
    @Test func replaceWithEmptyFilenameLeavesMetadataUntouched() {
        var config = SnapshotConfig(code: "x", language: .swift)
        config.metadata.filename = "Existing.swift"
        let loaded = FileInputLoader.LoadedFile(
            text: "SELECT 1", language: .sql, filename: "")

        loaded.apply(to: &config, replacing: true)

        #expect(config.code == "SELECT 1")
        #expect(config.language == .sql)
        // The pre-existing filename is preserved, never clobbered with "".
        #expect(config.metadata.filename == "Existing.swift")
    }

    /// Appending grows the document and, because the existing code already defines
    /// the language, deliberately keeps the current language rather than adopting
    /// the dropped file's. It also does not touch `metadata.filename`.
    @Test func appendKeepsLanguageAndGrowsText() {
        var config = SnapshotConfig(code: "let a = 1\n", language: .swift)
        let loaded = FileInputLoader.LoadedFile(
            text: "let b = 2\n", language: .python, filename: "more.py")

        loaded.apply(to: &config, replacing: false)

        #expect(config.code == "let a = 1\nlet b = 2\n")
        #expect(config.language == .swift)  // unchanged by an append
        #expect(config.metadata.filename == nil)  // append never records a filename
    }

    /// When the current code lacks a trailing newline, append inserts exactly one
    /// separator so the dropped block starts on its own line.
    @Test func appendInsertsSeparatorWhenMissingTrailingNewline() {
        var config = SnapshotConfig(code: "first", language: .swift)
        let loaded = FileInputLoader.LoadedFile(text: "second", language: .swift, filename: "")

        loaded.apply(to: &config, replacing: false)

        #expect(config.code == "first\nsecond")
    }

    /// When the current code already ends in a newline, append must not add a
    /// second blank line — it joins directly.
    @Test func appendDoesNotDoubleSeparatorWhenNewlinePresent() {
        var config = SnapshotConfig(code: "first\n", language: .swift)
        let loaded = FileInputLoader.LoadedFile(text: "second\n", language: .swift, filename: "")

        loaded.apply(to: &config, replacing: false)

        #expect(config.code == "first\nsecond\n")
    }
}

// MARK: - Sandbox entitlement (user-selected only, no broad file access)

@Suite("CS-028 sandbox entitlement")
struct FileInputSandboxEntitlementTests {
    /// The bundled entitlements, parsed from the source-of-truth plist so the check
    /// is independent of how the app is packaged. Located relative to this test
    /// file (the entitlements drive a build setting and are not copied as a bundle
    /// resource).
    private static func entitlements() throws -> [String: Any] {
        // .../vitrine/Tests/FileInputLoaderTests.swift → .../vitrine
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let url =
            repoRoot
            .appendingPathComponent("Vitrine")
            .appendingPathComponent("Resources")
            .appendingPathComponent("Vitrine.entitlements")
        let data = try Data(contentsOf: url)
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            "Vitrine.entitlements must be a property-list dictionary")
    }

    /// The App Sandbox is on and the one file entitlement is the *user-selected*
    /// read-write key — the only access a dropped file needs (its URL is a
    /// security-scoped, user-selected resource).
    @Test func sandboxIsOnAndFileAccessIsUserSelectedOnly() throws {
        let plist = try Self.entitlements()
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(plist["com.apple.security.files.user-selected.read-write"] as? Bool == true)
    }

    /// CS-028 acceptance: drop input adds **no broad file permissions**. None of
    /// the entitlement keys that would widen filesystem reach beyond the
    /// user-selected file may appear — so a future "make drops just work" change
    /// that grants blanket access is caught here.
    @Test func declaresNoBroadFileEntitlements() throws {
        let plist = try Self.entitlements()
        let forbidden = [
            "com.apple.security.files.all",
            "com.apple.security.files.downloads.read-only",
            "com.apple.security.files.downloads.read-write",
            "com.apple.security.files.bookmarks.app-scope",
            "com.apple.security.files.bookmarks.document-scope",
            "com.apple.security.temporary-exception.files.home-relative-path.read-write",
            "com.apple.security.temporary-exception.files.home-relative-path.read-only",
            "com.apple.security.temporary-exception.files.absolute-path.read-write",
            "com.apple.security.temporary-exception.files.absolute-path.read-only",
        ]
        for key in forbidden {
            #expect(plist[key] == nil, "Unexpected broad file entitlement: \(key)")
        }
        // Belt and suspenders: no key that grants absolute/home/downloads reach.
        let keys = Array(plist.keys)
        #expect(!keys.contains { $0.contains("files.all") })
        #expect(!keys.contains { $0.contains("temporary-exception.files") })
        #expect(!keys.contains { $0.contains("files.downloads") })
    }
}

// MARK: - Error messages

@Suite("FileInputLoader.LoadError")
struct FileInputLoaderErrorTests {
    /// Every error case carries a non-empty, user-facing message (the "clear
    /// message" acceptance) and they are distinct.
    @Test func everyErrorHasADistinctMessage() {
        let messages = [
            FileInputLoader.LoadError.binaryFile.message,
            FileInputLoader.LoadError.tooLarge.message,
            FileInputLoader.LoadError.unreadable.message,
        ]
        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(Set(messages).count == messages.count)
    }
}
