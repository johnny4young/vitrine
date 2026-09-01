import Foundation

/// Incrementally collects transport chunks without ever retaining bytes beyond its limit.
///
/// The capacity hint is deliberately small: reserving the entire public limit up front would
/// create the same memory spike this type is intended to prevent. Appends use subtraction-safe
/// arithmetic and reject an oversized chunk before mutating the accumulator.
nonisolated struct BoundedDataCollector: Sendable {
    enum Failure: Error, Equatable {
        case tooLarge
    }

    let limit: Int
    private(set) var data: Data

    init(limit: Int, initialCapacity: Int = 64 * 1024) {
        self.limit = max(0, limit)
        data = Data()
        data.reserveCapacity(min(self.limit, max(0, initialCapacity)))
    }

    mutating func append(_ chunk: Data) throws(Failure) {
        guard chunk.count <= limit - data.count else { throw .tooLarge }
        data.append(chunk)
    }
}
