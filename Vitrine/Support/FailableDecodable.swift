import Foundation

/// Decodes `T` element-wise-tolerantly: a malformed element yields `nil` instead of
/// failing the surrounding container, so one corrupt entry in a persisted or imported
/// array can never discard the valid ones (deep-review B9). Pair with `compactMap(\.value)`.
///
/// `nonisolated` so the `Decodable` conformance is unconditionally nonisolated under the
/// module's MainActor-default isolation, matching the house pattern.
nonisolated struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}
