import Foundation
import Testing

@testable import VitrineDomain

@Suite("Zlib output limits")
struct ZlibLimitTests {
    /// A raw DEFLATE stream holding nothing: one empty, final, fixed-Huffman block. Built
    /// by hand so the test does not depend on how `NSData` compresses empty input.
    private static let emptyStream = Data([0x03, 0x00])

    @Test func maximumIntegerLimitDoesNotOverflow() throws {
        let original = Data("small payload".utf8)
        let compressed = try Zlib.compress(original)
        #expect(try Zlib.decompress(compressed, maxOutputBytes: Int.max) == original)
    }

    @Test(arguments: [64 * 1024 - 1, 64 * 1024, 64 * 1024 + 1])
    func exactAndInsufficientLimitsAroundTheChunkBoundary(length: Int) throws {
        let original = Data(repeating: 65, count: length)
        let compressed = try Zlib.compress(original)
        #expect(try Zlib.decompress(compressed, maxOutputBytes: length) == original)
        #expect(throws: Zlib.ZlibError.outputTooLarge) {
            try Zlib.decompress(compressed, maxOutputBytes: length - 1)
        }
    }

    @Test func zeroLimitAcceptsOnlyAnEmptyStream() throws {
        #expect(try Zlib.decompress(Self.emptyStream, maxOutputBytes: 0).isEmpty)
        let nonempty = try Zlib.compress(Data([65]))
        #expect(throws: Zlib.ZlibError.outputTooLarge) {
            try Zlib.decompress(nonempty, maxOutputBytes: 0)
        }
    }

    @Test(arguments: [-1, -2, Int.min])
    func negativeLimitsFailClosedWithoutTrapping(limit: Int) throws {
        let nonempty = try Zlib.compress(Data([65]))
        #expect(throws: Zlib.ZlibError.decompressionFailed) {
            try Zlib.decompress(nonempty, maxOutputBytes: limit)
        }
        #expect(throws: Zlib.ZlibError.decompressionFailed) {
            try Zlib.decompress(Self.emptyStream, maxOutputBytes: limit)
        }
    }
}
