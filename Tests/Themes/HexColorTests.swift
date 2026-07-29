import SwiftUI
import Testing

@testable import Vitrine

@Suite("HexColor strict parsing")
struct HexColorTests {
    @Test func parsesAllSupportedLengths() {
        #expect(HexColor("#FFFFFF")?.hexString == "#FFFFFF")
        #expect(HexColor("000000")?.hexString == "#000000")
        #expect(HexColor("#FFF")?.hexString == "#FFFFFF")
        #expect(HexColor("#000")?.hexString == "#000000")
    }

    @Test func parsesAlphaAndShorthandAlpha() {
        // Full opacity drops the alpha suffix; partial opacity keeps it.
        #expect(HexColor("#112233FF")?.hexString == "#112233")
        #expect(HexColor("#11223380")?.hexString == "#112233" + "80")
        // RGBA shorthand doubles each nibble (8 → 88).
        let shorthand = HexColor("#1234")
        #expect(shorthand?.hexString == "#112233" + "44")
    }

    @Test func roundTripsThroughCanonicalUppercaseString() {
        let original = "#1e1e1e"
        let color = try! #require(HexColor(original))
        // Re-parsing the canonical string yields the same value: deterministic.
        let reparsed = try! #require(HexColor(color.hexString))
        #expect(color == reparsed)
        #expect(color.hexString == "#1E1E1E")
    }

    @Test func rejectsMalformedInput() {
        #expect(HexColor("") == nil)
        #expect(HexColor("#GGG") == nil)
        #expect(HexColor("#12") == nil)  // unsupported length
        #expect(HexColor("#1234567") == nil)  // 7 digits
        #expect(HexColor("rgb(1,2,3)") == nil)
        #expect(HexColor("not a color") == nil)
        // Fullwidth digits satisfy `isHexDigit` but stop the scanner mid-string;
        // they must be rejected, not decoded into a wrong-but-accepted color.
        #expect(HexColor("FFFFF\u{FF10}") == nil)  // trailing fullwidth ０
    }

    @Test func relativeLuminanceSeparatesDarkFromLight() {
        let black = try! #require(HexColor("#000000"))
        let white = try! #require(HexColor("#FFFFFF"))
        #expect(black.relativeLuminance < 0.5)
        #expect(white.relativeLuminance > 0.5)
    }

    @Test func colorIsReconstructedInSRGB() {
        // A captured hex color round-trips back to the same hex via the sRGB-pinned
        // `Color`, proving the value is display-independent (deterministic sizing).
        let color = try! #require(HexColor("#3A7BD5"))
        #expect(color.color.hexColor == color)
    }
}
