import Foundation
import Testing

@testable import VitrineDomain

@Suite("Zlib output limits")
struct ZlibLimitTests {
    @Test func maximumIntegerLimitDoesNotOverflow() throws {
        let original = Data("small payload".utf8)
        let compressed = try Zlib.compress(original)
        #expect(try Zlib.decompress(compressed, maxOutputBytes: Int.max) == original)
    }

    @Test func exactAndInsufficientLimitsAcrossChunkBoundary() throws {
        let original = Data(repeating: 65, count: 64 * 1024 + 1)
        let compressed = try Zlib.compress(original)
        #expect(try Zlib.decompress(compressed, maxOutputBytes: original.count) == original)
        #expect(throws: Zlib.ZlibError.outputTooLarge) {
            try Zlib.decompress(compressed, maxOutputBytes: original.count - 1)
        }
    }

    @Test func zeroAndNegativeLimitsKeepTheirErrorContract() throws {
        let empty = try Zlib.compress(Data())
        #expect(try Zlib.decompress(empty, maxOutputBytes: 0).isEmpty)
        let nonempty = try Zlib.compress(Data([65]))
        #expect(throws: Zlib.ZlibError.outputTooLarge) {
            try Zlib.decompress(nonempty, maxOutputBytes: 0)
        }
        #expect(throws: Zlib.ZlibError.decompressionFailed) {
            try Zlib.decompress(nonempty, maxOutputBytes: -1)
        }
    }
}
