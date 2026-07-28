import Testing

#if VITRINE_HOSTLESS_PROBE
    @testable import VitrineCoreProbe
#else
    @testable import Vitrine
#endif

@Suite("Build boundary probe")
struct BuildBoundaryProbeTests {
    @Test func detectsANSI() {
        #expect(ANSIParser.containsANSI("\u{1B}[32mok"))
    }

    @Test func parsesStyledText() {
        #expect(ANSIParser.parse("\u{1B}[32mok\u{1B}[0m").map(\.text) == ["ok"])
    }

    @Test func measuresWideCharacters() {
        #expect(CharacterWidth.displayWidth("界".unicodeScalars.first!) == 2)
    }

    @Test func measuresCombiningCharacters() {
        #expect(CharacterWidth.displayWidth("\u{0301}".unicodeScalars.first!) == 0)
    }
}
