import AppKit
import CoreText
import Testing
import VitrineDomain

@testable import VitrineRendering

@Suite("Styled syntax token fonts", .serialized)
struct StyledTokenFontTests {
    @Test(arguments: [Theme.oneDark, Theme.oneLight, Theme.github], [14.0, 22.0])
    func syntaxStylesPreserveTheSelectedFont(theme: Theme, size: Double) throws {
        let font = try #require(NSFont(name: "Menlo", size: size))
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        let fixtures: [(Language, String, [String])] = [
            (
                .swift,
                "// COMMENT_MARKER\nlet IDENTIFIER_MARKER = \"STRING_MARKER\"\nlet number = 4242",
                ["COMMENT_MARKER", "let", "IDENTIFIER_MARKER", "STRING_MARKER", "4242"]
            ),
            (
                .markdown,
                "**BOLDTOKEN**\n*ITALICTOKEN*\nPLAINTOKEN\n> QUOTETOKEN",
                ["BOLDTOKEN", "ITALICTOKEN", "PLAINTOKEN", "QUOTETOKEN"]
            ),
        ]

        for (language, source, markers) in fixtures {
            let highlighted = manager.attributedString(
                for: source, language: language, theme: theme, font: font)
            #expect(highlighted.string == source)
            for marker in markers {
                let actual = try tokenFont(marker, in: highlighted)
                #expect(actual.pointSize == font.pointSize, "\(theme.id) / \(marker)")
                #expect(actual.familyName == font.familyName, "\(theme.id) / \(marker)")
            }
            if language == .markdown {
                #expect(
                    try tokenFont("BOLDTOKEN", in: highlighted)
                        .fontDescriptor.symbolicTraits.contains(.bold))
                #expect(
                    try tokenFont("ITALICTOKEN", in: highlighted)
                        .fontDescriptor.symbolicTraits.contains(.italic))
            }
        }
    }

    @Test func regularOnlyFamiliesKeepLigatureSettingsAndAStyledVariant() throws {
        let base = CodeFont.applyingLigatures(false, to: try bundledJetBrainsMono(size: 22))
        let manager = HighlightManager.shared
        manager.resetCachesForTesting()
        let highlighted = manager.attributedString(
            for: "// COMMENT_MARKER\nlet value = 1", language: .swift, theme: .oneDark,
            font: base)
        let comment = try tokenFont("COMMENT_MARKER", in: highlighted)

        #expect(comment.familyName == base.familyName)
        #expect(comment.pointSize == base.pointSize)
        #expect(comment.textTransform != base.textTransform)
        #expect(
            comment.fontDescriptor.object(forKey: .featureSettings) as? NSArray
                == base.fontDescriptor.object(forKey: .featureSettings) as? NSArray)
        #expect(CodeFont.styled(base, bold: true, italic: false).familyName == base.familyName)
    }

    private func bundledJetBrainsMono(size: CGFloat) throws -> NSFont {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Vitrine/Resources/Fonts/JetBrainsMono-Regular.ttf")
            .standardizedFileURL
        let descriptors = try #require(
            CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
        let descriptor = try #require(descriptors.first)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    private func tokenFont(_ marker: String, in text: NSAttributedString) throws -> NSFont {
        let range = (text.string as NSString).range(of: marker)
        try #require(range.location != NSNotFound, "\(marker)")
        return try #require(
            text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    }
}
