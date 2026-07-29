import Testing

@testable import Vitrine

/// The name the save panel opens with (`ExportManager+File` calls this to seed it).
///
/// The derivation ladder is the whole behavior: the metadata chip wins, then the first
/// declared identifier in the code, then the plain app name — with anything path-ish or
/// spaced sanitized rather than emitted verbatim, since it becomes a filename.
@MainActor
@Suite("Export · suggested filename")
struct SuggestedFilenameTests {
    @Test("Save panel name derives from the metadata filename, then the code")
    func suggestedFilenameDerivation() {
        // 1. The metadata filename chip wins, extension dropped.
        var named = ExportTestFixtures.sampleConfig()
        named.metadata.filename = "ContentView.swift"
        #expect(SuggestedFilename.basename(for: named) == "ContentView")

        // Path-ish or spaced chips are sanitized, never emitted verbatim.
        named.metadata.filename = "Sources/App/My View.swift"
        #expect(SuggestedFilename.basename(for: named) == "My-View")

        // 2. Without a chip, the first declared identifier names the file.
        var code = ExportTestFixtures.sampleConfig()
        code.code = "import Foundation\n\nfunc renderCard() -> Int { 42 }"
        #expect(SuggestedFilename.basename(for: code) == "vitrine-renderCard")

        // 3. Nothing derivable falls back to the plain app name.
        var bare = ExportTestFixtures.sampleConfig()
        bare.code = "let answer = 42"
        #expect(SuggestedFilename.basename(for: bare) == "vitrine")
        var terminal = ExportTestFixtures.sampleConfig()
        terminal.language = .terminal
        terminal.code = "$ def not-code\n"
        #expect(SuggestedFilename.basename(for: terminal) == "vitrine")
    }
}
