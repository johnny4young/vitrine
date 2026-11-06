import Foundation
import Testing
import VitrineDomain

@testable import Vitrine
@testable import VitrineRendering

@MainActor
@Suite("Magic background model")
struct MagicBackgroundModelTests {
    private let derived = [
        GradientPreset.ocean.asCustomGradient, GradientPreset.sunset.asCustomGradient,
    ]

    private func request(
        _ model: MagicBackgroundModel, settings: AppSettings, advancing: Bool = false,
        gate: AsyncStream<Void>? = nil, undoManager: UndoManager? = nil
    ) {
        let derived = derived
        model.request(
            advancing: advancing, current: settings.style.background,
            input: { MagicBackgroundModel.Input(settings) },
            derive: {
                if let gate { for await _ in gate { break } }
                return derived
            },
            apply: { MagicBackgroundModel.apply($0, to: settings, undoManager: undoManager) })
    }

    @Test func aLaterChoiceWinsOverADerivationStillRunning() async {
        let settings = AppSettings(defaults: testDefaults())
        let model = MagicBackgroundModel()
        let (gate, open) = AsyncStream<Void>.makeStream()
        request(model, settings: settings, gate: gate)
        model.cancel()
        settings.style.background = .gradient(.forest)
        open.yield()
        await model.settle()
        #expect(settings.style.background == .gradient(.forest))
        #expect(model.gradients.isEmpty)
    }

    @Test func aResultForContentThatChangedIsDropped() async {
        let settings = AppSettings(defaults: testDefaults())
        let model = MagicBackgroundModel()
        let (gate, open) = AsyncStream<Void>.makeStream()
        request(model, settings: settings, gate: gate)
        settings.noteDocumentReplaced()
        open.yield()
        await model.settle()
        #expect(settings.style.background == .gradient(.aurora))
    }

    @Test func selectionAndShuffleOutliveTheControls() async {
        let settings = AppSettings(defaults: testDefaults())
        let model = MagicBackgroundModel()
        request(model, settings: settings)
        await model.settle()
        #expect(model.index(of: settings.style.background) == 0)

        // A reopened popover builds new controls over the same model.
        request(model, settings: settings, advancing: true)
        await model.settle()
        #expect(model.index(of: settings.style.background) == 1)
        request(model, settings: settings, advancing: true)
        await model.settle()
        #expect(model.index(of: settings.style.background) == 0)
        #expect(model.index(of: .gradient(.aurora)) == nil)
    }

    @Test func eachPickUndoesAsOneBackgroundChange() async {
        let settings = AppSettings(defaults: testDefaults())
        let model = MagicBackgroundModel()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        request(model, settings: settings, undoManager: undoManager)
        await model.settle()
        undoManager.endUndoGrouping()
        undoManager.beginUndoGrouping()
        request(model, settings: settings, advancing: true, undoManager: undoManager)
        await model.settle()
        undoManager.endUndoGrouping()
        #expect(settings.style.background == .customGradient(derived[1]))
        #expect(undoManager.undoActionName == String(localized: "Change Background"))

        undoManager.undo()
        #expect(settings.style.background == .customGradient(derived[0]))
        undoManager.undo()
        #expect(settings.style.background == .gradient(.aurora))
    }
}
