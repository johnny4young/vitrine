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

    @Test func advanceReadsTheGlyphCellWidth() {
        // CodeFont.advance reads the glyph advance via Core Text rather than running
        // NSAttributedString layout (which can raise an uncatchable NSException and abort
        // the whole test process on a degraded headless text subsystem). For a monospaced
        // font every glyph shares one advance, so a digit, a space, and a wide letter match.
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let zero = CodeFont.advance(of: "0", in: font)
        #expect(zero > 0)
        #expect(abs(CodeFont.advance(of: " ", in: font) - zero) < 0.01)
        #expect(abs(CodeFont.advance(of: "W", in: font) - zero) < 0.01)
    }
}

@Suite("Nerd Font glyph cascade")
struct NerdFontCascadeTests {
    @Test func installedNerdFontsKeepsOnlyAvailableInPreferenceOrder() {
        // The result follows candidate (preference) order, not the available set's
        // order, and drops anything not installed.
        let result = CodeFont.installedNerdFonts(
            among: ["A NF", "B NF", "C NF"], availableFamilies: ["C NF", "A NF"])
        #expect(result == ["A NF", "C NF"])
    }

    @Test func installedNerdFontsIsEmptyWhenNonePresent() {
        // The CI / no-Nerd-Font case: nothing resolves, so the cascade stays empty.
        #expect(
            CodeFont.installedNerdFonts(
                among: ["Symbols Nerd Font Mono"], availableFamilies: ["Menlo", "Arial"]
            ).isEmpty)
    }

    @Test func applyingEmptyCascadeLeavesTheFontUntouched() {
        // No Nerd Font installed → byte-identical font, so a host without one never
        // drifts from the previous rendering.
        let base = NSFont(name: "Menlo", size: 13)!
        let result = CodeFont.applying(cascade: [], to: base)
        #expect(result == base)
    }

    @Test func applyingACascadeAttachesItToTheFontDescriptor() {
        // Use Menlo (always installed) as a stand-in fallback so the wiring is
        // deterministic regardless of which Nerd Fonts the host has.
        let base = NSFont(name: "Menlo", size: 13)!
        let fallback = NSFontDescriptor(fontAttributes: [.family: "Menlo"])
        let result = CodeFont.applying(cascade: [fallback], to: base)

        let list = result.fontDescriptor.fontAttributes[.cascadeList] as? [NSFontDescriptor]
        #expect(list?.count == 1)
        #expect(result.pointSize == 13)
    }

    @Test func applyingACascadePreservesAnExistingOne() {
        // A base font that already carries a cascade list keeps it — the new
        // descriptors are appended after, not substituted.
        let existing = NSFontDescriptor(fontAttributes: [.family: "Courier"])
        let base = NSFont(name: "Menlo", size: 13)!
        let withExisting = NSFont(
            descriptor: base.fontDescriptor.addingAttributes([.cascadeList: [existing]]), size: 0)!

        let added = NSFontDescriptor(fontAttributes: [.family: "Monaco"])
        let result = CodeFont.applying(cascade: [added], to: withExisting)

        let list = result.fontDescriptor.fontAttributes[.cascadeList] as? [NSFontDescriptor]
        #expect(list?.count == 2)
        #expect(list?.first?.fontAttributes[.family] as? String == "Courier")
        #expect(list?.last?.fontAttributes[.family] as? String == "Monaco")
    }
}
