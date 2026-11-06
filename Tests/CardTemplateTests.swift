import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@Suite("Card templates")
struct CardTemplateTests {
    private func link(_ query: String) -> URL { URL(string: "vitrine://card?\(query)")! }

    @Test func builtInsHaveUniqueIDsAndAcceptStyleSlots() {
        let ids = CardTemplate.builtIns.map(\.id)
        #expect(Set(ids).count == ids.count)
        for template in CardTemplate.builtIns {
            #expect(CardTemplate.named(template.id) == template)
            #expect(template.slots.contains(.theme) && template.slots.contains(.accent))
            #expect(!template.displayName.isEmpty)
        }
        #expect(CardTemplate.named("missing") == nil)
    }

    @Test func aLinkFillsTheTemplateAndKeepsTheBaseStyle() throws {
        let fill = try CardTemplateLink.fill(
            from: link("template=release&title=Vitrine%201.3.0&project=vitrine&accent=SUNSET"))
        let base = SocialCardModel(
            title: "Old", codeExcerpt: "old()", author: "@old", showLogo: true,
            theme: .nord, fontSize: 30)
        let card = fill.card(onto: base)
        #expect(card.template == .standard)
        #expect(card.title == "Vitrine 1.3.0")
        #expect(card.project == "vitrine")
        #expect(card.background == .gradient(.sunset))
        // Slots the link leaves out are cleared; style the link leaves out stays.
        #expect(card.codeExcerpt.isEmpty && card.author == nil)
        #expect(card.theme == .nord && card.showLogo && card.fontSize == 30)
    }

    @Test func choiceSlotsResolveOnlyAllowListedValues() throws {
        let fill = try CardTemplateLink.fill(
            from: link("template=snippet&code=let%20x%20%3D%201&language=Python&theme=dracula"))
        let card = fill.card(onto: SocialCardModel())
        #expect(card.template == .codeFocus)
        #expect(card.language == .python)
        #expect(card.theme == .dracula)
        #expect(card.codeExcerpt == "let x = 1")
        for bad in ["language=terminal", "language=cobol", "theme=../x", "accent=%23ff0000"] {
            #expect(throws: CardTemplate.FillError.self) {
                try CardTemplateLink.fill(from: link("template=snippet&\(bad)"))
            }
        }
    }

    @Test func malformedOrForeignLinksAreRefused() {
        let refused: [(String, CardTemplate.FillError)] = [
            ("vitrine://card", .malformedLink),
            ("vitrine://card/path?template=release", .malformedLink),
            ("vitrine://card?template=release#x", .malformedLink),
            ("vitrine://me@card?template=release", .malformedLink),
            ("vitrine://card:8080?template=release", .malformedLink),
            ("https://card?template=release", .malformedLink),
            ("vitrine://card?template", .malformedLink),
            ("vitrine://card?title=x", .unknownTemplate),
            ("vitrine://card?template=nope", .unknownTemplate),
            ("vitrine://card?template=release&image=/etc/hosts", .unsupportedSlot("image")),
            ("vitrine://card?template=release&handle=x", .unsupportedSlot("handle")),
            ("vitrine://card?template=release&title=a&title=b", .duplicateSlot("title")),
        ]
        for (string, error) in refused {
            #expect(throws: error) { try CardTemplateLink.fill(from: URL(string: string)!) }
        }
    }

    @Test func overLongAndControlCharacterValuesAreRefused() {
        let long = String(repeating: "a", count: CardTemplate.Slot.title.maxLength + 1)
        #expect(throws: CardTemplate.FillError.invalidValue(.title)) {
            try CardTemplateLink.fill(from: link("template=release&title=\(long)"))
        }
        for value in ["a%00b", "a%0Ab", "a%E2%80%AEb"] {
            #expect(throws: CardTemplate.FillError.invalidValue(.title)) {
                try CardTemplateLink.fill(from: link("template=release&title=\(value)"))
            }
        }
        let huge = String(repeating: "x", count: CardTemplateLink.maxLength)
        #expect(throws: CardTemplate.FillError.malformedLink) {
            try CardTemplateLink.fill(from: link("template=release&title=\(huge)"))
        }
    }

    @Test func codeKeepsNewlinesAndBlankValuesCountAsAbsent() throws {
        let fill = try CardTemplateLink.fill(
            from: link("template=release&code=a()%0D%0A%09b()&subtitle=%20%20"))
        #expect(fill.values[.code] == "a()\n\tb()")
        #expect(fill.values[.subtitle] == nil)
    }

    @Test func aBuiltLinkRoundTripsReservedAndNonASCIIText() throws {
        let fill = try CardTemplate.Fill(
            template: .announcement,
            values: [.title: "Ünïcode & more = 100% + ✨", .handle: "@jane", .accent: "ocean"])
        let url = try #require(CardTemplateLink.url(for: fill))
        #expect(url.absoluteString.hasPrefix("vitrine://card?template=announcement&title="))
        #expect(try CardTemplateLink.fill(from: url) == fill)
    }

    @Test func carryingACardKeepsOnlyTheTemplatesContentSlots() {
        let card = SocialCardModel(
            title: "T", subtitle: "S", codeExcerpt: "c()", language: .go, author: "@a",
            project: "p")
        let fill = CardTemplate.Fill(template: .announcement, carrying: card)
        #expect(fill.values == [.title: "T", .subtitle: "S", .handle: "@a", .project: "p"])
        let snippet = CardTemplate.Fill(template: .snippet, carrying: card).card(onto: card)
        #expect(snippet.template == .codeFocus)
        #expect(snippet.codeExcerpt == "c()" && snippet.language == .go)
        #expect(snippet.subtitle == nil && snippet.project == nil)
    }
}

@MainActor
@Suite("Card template opening")
struct CardTemplateOpeningTests {
    private func environment() -> AppEnvironment {
        AppEnvironment(
            defaults: testDefaults(), entitlements: Entitlements(provider: FreeProvider()))
    }

    private func controller(_ environment: AppEnvironment) -> SocialCardWindowController {
        SocialCardWindowController(
            environment: environment, feedback: .noOp, presentation: .noOp)
    }

    @Test func applyingATemplateIsUndoableAndRedoable() throws {
        let environment = environment()
        let original = SocialCardModel(title: "Mine", subtitle: "unsaved", project: "p")
        environment.appSettings.socialCard = original
        let undo = UndoManager()
        undo.groupsByEvent = false
        let fill = try CardTemplate.Fill(template: .snippet, values: [.title: "From link"])

        undo.beginUndoGrouping()
        controller(environment).apply(fill, undoManager: undo)
        undo.endUndoGrouping()
        let applied = environment.appSettings.socialCard
        #expect(applied.title == "From link" && applied.template == .codeFocus)
        #expect(undo.undoActionName == String(localized: "Apply Card Template"))

        undo.undo()
        #expect(environment.appSettings.socialCard == original)
        undo.redo()
        #expect(environment.appSettings.socialCard == applied)
    }

    @Test func applyingTheSameCardRegistersNoUndo() throws {
        let environment = environment()
        let fill = try CardTemplate.Fill(template: .release, values: [.title: "Same"])
        environment.appSettings.socialCard = fill.card(onto: environment.appSettings.socialCard)
        let undo = UndoManager()
        controller(environment).apply(fill, undoManager: undo)
        #expect(!undo.canUndo)
    }

    @Test func thePaletteFillUsesTheEditorCodeAndCarriesTheCardCopy() {
        let card = SocialCardModel(title: "Keep", codeExcerpt: "old()", author: "@me")
        let editor = SnapshotConfig(code: "\n  first()\n  second()\n", language: .terminal)
        let fill = SocialCardWindowController.paletteFill(.snippet, card: card, editor: editor)
        #expect(fill.values[.code] == "first()\nsecond()")
        #expect(fill.values[.language] == Language.plaintext.rawValue)
        #expect(fill.values[.title] == "Keep" && fill.values[.handle] == "@me")

        let empty = SocialCardWindowController.paletteFill(
            .snippet, card: card, editor: SnapshotConfig(code: "", language: .rust))
        #expect(empty.values[.code] == "old()")
        #expect(empty.values[.language] == Language.swift.rawValue)
    }

    @Test func thePaletteOffersOneCommandPerTemplate() {
        let ids = EditorView(environment: environment()).cardTemplateCommands.map(\.id)
        #expect(ids == CardTemplate.builtIns.map { "card.\($0.id)" })
    }

    @Test func cardLinksRouteToTheCardWindowAndInvalidOnesAreIgnored() {
        #expect(AppDelegate.handoffRoute(for: URL(string: "VITRINE://CARD?x")!) == .cardTemplate)
        let environment = environment()
        var opened: [CardTemplate.Fill] = []
        let delegate = AppDelegate(
            environment: environment, feedback: CaptureFeedbackPresenter(display: .noOp),
            editorPresentation: .noOp, loadEditor: { _ in Issue.record("editor loaded") },
            openCard: { opened.append($0) })
        delegate.openHandoff(URL(string: "vitrine://card?template=release&title=Hi")!)
        delegate.openHandoff(URL(string: "vitrine://card?template=release&path=/tmp")!)
        #expect(opened.count == 1)
        #expect(opened.first?.values[.title] == "Hi")
    }
}
