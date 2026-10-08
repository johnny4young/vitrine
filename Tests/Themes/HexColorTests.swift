import SwiftUI
import Testing
import VitrineDomain
import VitrineRendering

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

    /// `Scanner` accepts a `0x` prefix and skips leading whitespace, which used to decode
    /// `0x1E1E1E` as a nearly transparent RRGGBBAA color.
    @Test func rgbaParserRejectsPrefixesTheLengthCheckMiscounts() {
        #expect(RGBAColor(hex: "0x1E1E1E") == nil)
        #expect(RGBAColor(hex: "0X1E1") == nil)
        #expect(RGBAColor(hex: " FFF") == RGBAColor(red: 1, green: 1, blue: 1, opacity: 1))
    }

    @Test(arguments: [
        "#1E1E1E", "1e1e1e", "#FFF", "#1234", "#11223380", " #ABC ", "0x1E1E1E", "0X1E1",
        "#GGG", "", "#", "#12", "#1234567", "FFFFF\u{FF10}", "+FFF", "-FFF",
    ])
    func hexColorAndRGBAColorAgree(_ input: String) {
        let strict = HexColor(input)
        let rgba = RGBAColor(hex: input)
        #expect((strict == nil) == (rgba == nil))
        if let strict, let rgba {
            #expect(
                RGBAColor(
                    red: strict.red, green: strict.green, blue: strict.blue, opacity: strict.alpha)
                    == rgba)
        }
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
