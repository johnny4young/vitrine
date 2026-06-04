import AppKit
import Testing

@testable import Vitrine

@Suite("Bundled fonts")
struct FontTests {
    @Test(
        arguments: [
            "JetBrains Mono", "Fira Code", "Hack", "IBM Plex Mono",
            "Roboto Mono", "Space Mono", "Ubuntu Mono", "Geist Mono",
        ])
    func bundledFontIsRegistered(_ family: String) {
        #expect(NSFont(name: family, size: 13) != nil, "bundled font '\(family)' is not registered")
    }

    @Test func catalogIsComplete() {
        #expect(CodeFont.all.contains(CodeFont.default))
        #expect(CodeFont.all.contains("SF Mono"))
        #expect(CodeFont.bundled.count == 8)
        #expect(CodeFont.all.count >= 10)
    }
}
