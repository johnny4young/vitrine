import Foundation
import Testing

@testable import Vitrine

@Suite("Custom theme store")
struct CustomThemeStoreTests {
    @Test func newStoreHasNoCustomThemesButOffersTheBuiltIns() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        #expect(store.customThemes.isEmpty)
        // The catalog always leads with the immutable built-ins.
        #expect(store.allThemes.prefix(Theme.builtIns.count).map(\.id) == Theme.builtIns.map(\.id))
    }

    @Test func addedThemeGetsAFreshNonBuiltInIDAndPersists() {
        let defaults = ThemeTestFixtures.freshDefaults()
        let store = CustomThemeStore(defaults: defaults)
        let added = store.addTheme(named: "Mine", palette: ThemeTestFixtures.samplePalette())

        #expect(added.id.hasPrefix("custom."))
        #expect(!Theme.builtInIDs.contains(added.id))
        #expect(store.customThemes.map(\.id) == [added.id])

        // A second store over the same defaults restores the persisted theme.
        let reopened = CustomThemeStore(defaults: defaults)
        #expect(reopened.customThemes.count == 1)
        #expect(reopened.customThemes.first?.displayName == "Mine")
        #expect(reopened.customThemes.first?.palette == ThemeTestFixtures.samplePalette())
    }

    @Test func duplicateNamesAreDisambiguated() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let first = store.addTheme(named: "Twin", palette: ThemeTestFixtures.samplePalette())
        let second = store.addTheme(named: "Twin", palette: ThemeTestFixtures.samplePalette())
        #expect(first.displayName == "Twin")
        #expect(second.displayName == "Twin 2")
    }

    @Test func importRejectsMoreThanOneThousandDecodedThemes() throws {
        let themes = (0...CustomThemeDocument.maximumThemeCount).map { index in
            Theme(
                id: "custom.test-\(index)",
                displayName: "Theme \(index)",
                palette: ThemeTestFixtures.samplePalette())
        }
        let data = try CustomThemeDocument(themes: themes).jsonData()
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())

        #expect(throws: CustomThemeDocument.ImportError.tooManyThemes) {
            _ = try store.importThemes(from: data)
        }
        #expect(store.customThemes.isEmpty)
    }

    @Test func fileImportRejectsInputsAboveOneMegabyte() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineThemeImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("themes.json")
        try Data(repeating: 0x20, count: CustomThemeFileExchange.maximumByteCount + 1)
            .write(to: file)

        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        #expect(throws: CustomThemeDocument.ImportError.fileTooLarge) {
            _ = try CustomThemeFileExchange.importFile(at: file, store: store)
        }
        #expect(store.customThemes.isEmpty)
    }

    @Test func emptyNameCollapsesToAFriendlyDefault() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let added = store.addTheme(named: "   ", palette: ThemeTestFixtures.samplePalette())
        #expect(added.displayName == "Custom Theme")
    }

    @Test func builtInIDsAlwaysResolveToTheBuiltInTheme() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        for builtIn in Theme.builtIns {
            let resolved = store.theme(withID: builtIn.id)
            #expect(resolved.id == builtIn.id)
            #expect(resolved.isBuiltIn)
            #expect(resolved.palette == nil)  // a built-in carries no custom palette
        }
    }

    @Test func unknownIDFallsBackToOneDark() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        #expect(store.theme(withID: "does-not-exist").id == Theme.oneDark.id)
    }

    @Test func customThemeResolvesByItsOwnID() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let added = store.addTheme(named: "Resolvable", palette: ThemeTestFixtures.samplePalette())
        let resolved = store.theme(withID: added.id)
        #expect(resolved.id == added.id)
        #expect(resolved.palette == ThemeTestFixtures.samplePalette())
        #expect(!resolved.isBuiltIn)
    }

    @Test func renamingOrDeletingABuiltInIDIsANoOp() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        #expect(store.rename(id: Theme.oneDark.id, to: "Hacked") == false)
        #expect(store.delete(id: Theme.oneDark.id) == false)
        #expect(store.isBuiltIn(id: Theme.oneDark.id))
        // The built-in catalog is untouched and still resolves to its real name.
        #expect(store.theme(withID: Theme.oneDark.id).displayName == "One Dark")
    }

    @Test func renameAndDeleteAffectOnlyCustomThemes() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let added = store.addTheme(named: "Before", palette: ThemeTestFixtures.samplePalette())

        #expect(store.rename(id: added.id, to: "After") == true)
        #expect(store.theme(withID: added.id).displayName == "After")

        #expect(store.delete(id: added.id) == true)
        #expect(store.customThemes.isEmpty)
        // After deletion the id falls back to the built-in default.
        #expect(store.theme(withID: added.id).id == Theme.oneDark.id)
    }

    @Test func importIsPurelyAdditiveAndRekeysIDs() throws {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        let data = try ThemeTestFixtures.sampleThemeFileData(name: "Imported")

        let firstAdded = try store.importThemes(from: data)
        #expect(firstAdded.count == 1)
        #expect(store.customThemes.count == 1)

        // Importing the same file again adds a second, distinctly-keyed copy rather
        // than overwriting the first.
        let secondAdded = try store.importThemes(from: data)
        #expect(secondAdded.count == 1)
        #expect(store.customThemes.count == 2)
        #expect(secondAdded[0].id != firstAdded[0].id)
        #expect(secondAdded[0].displayName == "Imported 2")  // de-duplicated name
    }

    @Test func importingABadFileLeavesTheLiveStateUntouched() {
        let store = CustomThemeStore(defaults: ThemeTestFixtures.freshDefaults())
        store.addTheme(named: "Keep Me", palette: ThemeTestFixtures.samplePalette())
        let before = store.customThemes

        #expect(throws: CustomThemeDocument.ImportError.self) {
            try store.importThemes(from: Data("garbage".utf8))
        }
        // A failed import is atomic: nothing was added or removed.
        #expect(store.customThemes == before)
    }
}
