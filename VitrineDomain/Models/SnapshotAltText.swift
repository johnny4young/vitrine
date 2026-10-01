import Foundation

/// Optional, content-bound alternative text. It is never a reusable style default.
public struct SnapshotAltText: Equatable, Codable, Sendable {
    public static let maximumLength = 1_024
    public let text: String

    public enum ValidationError: Error, Equatable, Sendable { case tooLong }

    /// Empty input means no description. Reject excess text rather than truncating it.
    public static func normalized(_ input: String?) throws -> SnapshotAltText? {
        guard let input = SnapshotMetadata.normalized(input) else { return nil }
        guard input.count <= maximumLength else { throw ValidationError.tooLong }
        return SnapshotAltText(text: input)
    }

    private init(text: String) { self.text = text }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let input = try container.decode(String.self)
        guard let value = try Self.normalized(input) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Empty alternative text")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
