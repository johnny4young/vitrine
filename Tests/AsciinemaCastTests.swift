import Foundation
import Testing

@testable import Vitrine

/// The asciinema `.cast` importer: JSON-lines recordings replay their output
/// events into terminal bytes for the existing ANSI pipeline, and anything that
/// is not a real recording falls back to the ordinary text-load path.
@Suite("Asciinema cast import")
struct AsciinemaCastTests {
    private let esc = "\u{1B}"
    private let header = #"{"version": 2, "width": 80, "height": 24}"#

    @Test func concatenatesOutputEvents() {
        let cast = """
            \(header)
            [0.1, "o", "$ ls\\r\\n"]
            [0.5, "o", "README.md\\r\\n"]
            """
        #expect(AsciinemaCast.terminalText(from: cast) == "$ ls\r\nREADME.md\r\n")
    }

    @Test func skipsNonOutputEvents() {
        // Input echoes, resizes, and markers carry no screen bytes.
        let cast = """
            \(header)
            [0.1, "i", "l"]
            [0.2, "r", "120x40"]
            [0.3, "o", "ok"]
            [0.4, "m", "chapter 1"]
            """
        #expect(AsciinemaCast.terminalText(from: cast) == "ok")
    }

    @Test func decodesEscapedANSIInEventPayloads() {
        let cast = header + "\n" + #"[0.1, "o", "\u001b[32mok\u001b[0m\r\n"]"#
        #expect(AsciinemaCast.terminalText(from: cast) == "\(esc)[32mok\(esc)[0m\r\n")
    }

    @Test func acceptsVersion3AndRejectsOthers() {
        let v3 = #"{"version": 3}"# + "\n" + #"[0.1, "o", "hi"]"#
        #expect(AsciinemaCast.terminalText(from: v3) == "hi")
        let v1 = #"{"version": 1, "stdout": []}"#
        #expect(AsciinemaCast.terminalText(from: v1) == nil)
    }

    @Test func rejectsNonCastContent() {
        #expect(AsciinemaCast.terminalText(from: "let x = 1") == nil)
        #expect(AsciinemaCast.terminalText(from: "") == nil)
        // Ordinary JSON has no version header and must not masquerade as a cast.
        #expect(AsciinemaCast.terminalText(from: #"{"name": "config"}"#) == nil)
    }

    @Test func skipsMalformedEventLines() {
        // A truncated trailing event (a recording cut mid-write) must not lose the
        // rest of the session.
        let cast = header + "\n" + #"[0.1, "o", "kept"]"# + "\n" + #"[0.2, "o", "trunc"#
        #expect(AsciinemaCast.terminalText(from: cast) == "kept")
    }

    @Test func recognizesTheCastExtension() {
        #expect(AsciinemaCast.isCastFilename("demo.cast"))
        #expect(AsciinemaCast.isCastFilename("Demo.CAST"))
        #expect(!AsciinemaCast.isCastFilename("demo.txt"))
        #expect(!AsciinemaCast.isCastFilename("cast"))
    }

    @Test func decodeRoutesCastFilesToTheTerminalRenderer() throws {
        let cast = header + "\n" + #"[0.1, "o", "\u001b[32mok\u001b[0m\r\n"]"#
        let loaded = try FileInputLoader.decode(data: Data(cast.utf8), filename: "demo.cast")
        #expect(loaded.language == .terminal)
        #expect(loaded.text == "\(esc)[32mok\(esc)[0m\r\n")
        #expect(loaded.filename == "demo.cast")
    }

    @Test func malformedCastFileFallsBackToPlainLoad() throws {
        let text = "not a recording"
        let loaded = try FileInputLoader.decode(data: Data(text.utf8), filename: "demo.cast")
        #expect(loaded.text == text)
    }
}
