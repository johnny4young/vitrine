import Foundation
import Observation
import VitrineDomain
import VitrineRendering

/// One window's derived backgrounds. It outlives the inspector, so a canvas-mode popover that
/// reopens keeps the selection and Shuffle's place.
@Observable
final class MagicBackgroundModel {
    /// What a derivation read. A result whose input changed meanwhile is dropped.
    struct Input: Equatable {
        let foregroundImage: ImageReference?
        let documentGeneration: Int
        let theme: Theme
        let language: Language
        let terminalPalette: TerminalPaletteMode

        init(_ settings: AppSettings) {
            foregroundImage = settings.style.foregroundImage
            documentGeneration = settings.documentGeneration
            theme = settings.style.theme
            language = settings.style.language
            terminalPalette = settings.style.terminalPalette
        }
    }

    private(set) var gradients: [CustomGradient] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Which derived gradient `background` is, if it still is one.
    func index(of background: VitrineDomain.BackgroundStyle) -> Int? {
        guard case .customGradient(let gradient) = background else { return nil }
        return gradients.firstIndex(of: gradient)
    }

    /// Waits for the derivation in flight, if any.
    func settle() async { await task?.value }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Derives again, so Shuffle follows edits, then applies the first variant, or with
    /// `advancing` the one after `current`.
    func request(
        advancing: Bool, current: VitrineDomain.BackgroundStyle, input: @escaping () -> Input,
        derive: @escaping () async -> [CustomGradient],
        apply: @escaping (CustomGradient) -> Void
    ) {
        let next = advancing ? (index(of: current) ?? -1) + 1 : 0
        let started = input()
        cancel()
        task = Task {
            let derived = await derive()
            guard !Task.isCancelled else { return }
            task = nil
            guard !derived.isEmpty, input() == started else { return }
            gradients = derived
            apply(derived[next % derived.count])
        }
    }

    /// One undo step per pick, holding the previous background in memory only.
    static func apply(
        _ gradient: CustomGradient, to settings: AppSettings, undoManager: UndoManager?
    ) {
        let previous = settings.style.background
        undoManager?.registerUndo(withTarget: settings) { settings in
            settings.style.background = previous
        }
        undoManager?.setActionName(String(localized: "Change Background"))
        settings.style.background = .customGradient(gradient)
    }
}
