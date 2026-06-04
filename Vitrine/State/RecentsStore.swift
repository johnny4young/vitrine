import Combine
import Foundation

/// Persists the last `limit` captures (CS-013): newest first, capped, and
/// de-duplicated by code. `UserDefaults` is injectable so it can be unit-tested.
final class RecentsStore: ObservableObject {
    static let shared = RecentsStore()
    static let limit = 10

    @Published private(set) var captures: [Capture]

    private let defaults: UserDefaults
    private let key = "recentCaptures"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Capture].self, from: data)
        {
            captures = decoded
        } else {
            captures = []
        }
    }

    /// Inserts `capture` at the front, removing any existing entry with identical
    /// code, and caps the list at `limit`.
    func add(_ capture: Capture) {
        captures.removeAll { $0.code == capture.code }
        captures.insert(capture, at: 0)
        if captures.count > Self.limit {
            captures = Array(captures.prefix(Self.limit))
        }
        persist()
    }

    func clear() {
        captures.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(captures) {
            defaults.set(data, forKey: key)
        }
    }
}
