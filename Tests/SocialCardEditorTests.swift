import AppKit
import Foundation
import Testing

@testable import Vitrine

// CS-041 — the social-card editor surface (app integration). The card model and
// renderer are covered by `SocialCardTests`; these pin the seams the editor adds:
// the working card's persistence in `AppSettings` and the File-menu command wiring.

@Suite("Social card settings persistence")
@MainActor
struct SocialCardPersistenceTests {
    /// A card with every field set away from the model defaults, already normalized
    /// (trimmed text, ≤8 excerpt lines, in-range font) so it round-trips unchanged.
    private func sampleCard() -> SocialCardModel {
        SocialCardModel(
            title: "Ship beautiful code",
            subtitle: "in one shortcut",
            codeExcerpt: "let answer = 42",
            language: .swift,
            author: "@jane",
            project: "vitrine",
            showLogo: true,
            template: .codeFocus,
            theme: .nord,
            background: .gradient(.ocean),
            fontSize: 26)
    }

    @Test func theWorkingCardRoundTripsThroughUserDefaults() {
        let suite = "VitrineSocialCardPersistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let card = sampleCard()
        let settings = AppSettings(defaults: defaults)
        settings.socialCard = card  // post-init assignment → persists via didSet

        // A fresh settings instance over the same store restores the persisted card,
        // proving the @Published/didSet write and the init read agree.
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.socialCard == card)
    }

    @Test func aFreshStoreYieldsTheDefaultCard() {
        let suite = "VitrineSocialCardDefault-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.socialCard == SocialCardModel())
    }

    @Test func resetToDefaultsClearsTheWorkingCard() {
        let suite = "VitrineSocialCardReset-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.socialCard = sampleCard()
        settings.resetToDefaults()
        #expect(settings.socialCard == SocialCardModel())
    }

    @Test func aCorruptStoredBlobFallsBackToTheDefaultCard() {
        // CS-050 posture: a hand-edited or garbage blob never traps; it degrades to a
        // fresh default card.
        let suite = "VitrineSocialCardCorrupt-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: SettingsCodec.Keys.socialCard)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.socialCard == SocialCardModel())
    }
}

@Suite("Social card command and menu")
@MainActor
struct SocialCardCommandTests {
    @Test func newSocialCardIsAppScoped() {
        // It opens a window; it is not an editor/document command, so it stays enabled
        // regardless of which window is key, and never gates on code being present.
        #expect(!VitrineCommand.newSocialCard.isEditorScoped)
        #expect(!VitrineCommand.newSocialCard.requiresCode)
    }

    @Test func newSocialCardHasNoKeyboardShortcut() {
        // ⌘N is taken by New Editor Window; the card command ships shortcut-free rather
        // than reaching for a non-conventional combination.
        #expect(VitrineCommand.newSocialCard.keyEquivalent == nil)
        #expect(VitrineCommand.newSocialCard.modifiers == [])
    }

    @Test func newSocialCardTitleOpensItsWindowWithoutEllipsis() {
        // Like Open Editor, it opens the composer directly — no further dialog — so it
        // carries no trailing ellipsis (matching CommandTests' ellipsis convention).
        #expect(!VitrineCommand.newSocialCard.title.hasSuffix("…"))
        #expect(!VitrineCommand.newSocialCard.title.isEmpty)
    }

    @Test func fileMenuExposesNewSocialCardTargetingTheAppResponder() {
        let file = AppMenu.make().items.compactMap(\.submenu).first { $0.title == "File" }
        let item = file?.items.first {
            $0.accessibilityIdentifier() == VitrineCommand.newSocialCard.accessibilityIdentifier
        }
        #expect(item != nil, "New Social Card must be in the File menu")
        #expect(item?.target is AppCommandResponder)
        #expect(item?.action == #selector(AppCommandResponder.openSocialCardEditor(_:)))
        // App-scoped commands carry no key equivalent in the menu.
        #expect(item?.keyEquivalent == "")
    }

    @Test func theSocialCardWindowIsNotEditorScopedByIdentifier() {
        // `EditorCommandResponder.isEditorKey` enables the export commands when the key
        // window's identifier starts with "editor-window"; the card window must not, or
        // it would wrongly enable the editor's Copy/Save/Share while it is key.
        #expect(!SocialCardWindowController.windowIdentifier.hasPrefix("editor-window"))
    }
}
