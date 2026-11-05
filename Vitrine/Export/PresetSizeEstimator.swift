import Observation
import VitrineDomain
import VitrineRendering

/// Measures each preset's file for the multi-size sheet's total: once per input, one preset at
/// a time. Rendering stays on the main actor, as in the export, so documents above
/// ``maximumMeasuredBytes`` are not measured at all.
@Observable
final class PresetSizeEstimator {
    /// The inputs that change a file's bytes. Any change discards every measurement.
    struct Input: Equatable {
        var config: SnapshotConfig
        var format: ExportFormat
        var profile: ColorProfile
    }

    /// Render cost grows faster than the document: one preset blocks 44 ms at 1.3 KB and
    /// 176 ms at 3.4 KB, so this stays below the point where a block is noticeable.
    static let maximumMeasuredBytes = 2 * 1024

    private var input: Input?
    private var measuredBytes: [String: Int] = [:]
    private var failedPresets: Set<String> = []

    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let measurePreset: (ExportPreset, Input) async -> Int?
    @ObservationIgnored private var currentRun = 0

    init(
        debounce: Duration = .milliseconds(300),
        measurePreset: @escaping (ExportPreset, Input) async -> Int? = { preset, input in
            await ExportManager.estimatedPresetBytes(
                input.config, preset: preset, format: input.format, profile: input.profile)
        }
    ) {
        self.debounce = debounce
        self.measurePreset = measurePreset
    }

    /// `nil` until every selected preset is measured, so a partial sum never reads as the total.
    func total(of selected: Set<String>, for input: Input) -> Int? {
        guard self.input == input, !selected.isEmpty else { return nil }
        var total = 0
        for id in selected {
            guard let bytes = measuredBytes[id] else { return nil }
            total += bytes
        }
        return total
    }

    /// Waits out a burst of toggles, then renders what has neither a result nor a failure.
    /// Ends at the next preset once its task is cancelled or ``stop()`` is called.
    func measure(_ presets: [ExportPreset], for input: Input) async {
        currentRun += 1
        let run = currentRun
        if self.input != input {
            self.input = input
            measuredBytes = [:]
            failedPresets = []
        }
        guard input.config.code.utf8.count <= Self.maximumMeasuredBytes else { return }
        let missing = presets.filter {
            measuredBytes[$0.id] == nil && !failedPresets.contains($0.id)
        }
        guard !missing.isEmpty else { return }
        try? await Task.sleep(for: debounce)
        for preset in missing {
            guard !Task.isCancelled, run == currentRun else { return }
            // A replaced run may have finished this preset during the debounce.
            guard measuredBytes[preset.id] == nil, !failedPresets.contains(preset.id) else {
                continue
            }
            let bytes = await measurePreset(preset, input)
            // A result stays valid for its input, even if the run that asked was replaced.
            guard self.input == input else { return }
            if let bytes {
                measuredBytes[preset.id] = bytes
            } else {
                failedPresets.insert(preset.id)
            }
            await Task.yield()
        }
    }

    func stop() {
        currentRun += 1
    }
}
