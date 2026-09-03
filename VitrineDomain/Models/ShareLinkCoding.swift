import Compression
import Foundation

/// zlib compression for the share-link payload. A code snippet is repetitive text that
/// compresses well, keeping the encoded `vitrine://open` URL short.
/// Backed by Foundation's `NSData` compression (no third-party dependency); the
/// throwing surface lets the caller treat a corrupt payload as a malformed link rather
/// than trapping.
public enum Zlib {
    public enum ZlibError: Error, Equatable {
        case compressionFailed
        case decompressionFailed
        case outputTooLarge
    }

    public static func compress(_ data: Data) throws -> Data {
        do { return try (data as NSData).compressed(using: .zlib) as Data } catch {
            throw ZlibError.compressionFailed
        }
    }

    /// Decompresses `data` with a caller-provided output ceiling. The stream is stopped
    /// as soon as the next chunk would cross the limit, before a compressed payload can
    /// expand into an unbounded allocation.
    public static func decompress(_ data: Data, maxOutputBytes: Int) throws -> Data {
        guard !data.isEmpty, maxOutputBytes >= 0 else { throw ZlibError.decompressionFailed }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        guard
            compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
                != COMPRESSION_STATUS_ERROR
        else {
            stream.deallocate()
            throw ZlibError.decompressionFailed
        }
        defer {
            compression_stream_destroy(stream)
            stream.deallocate()
        }

        let bufferSize = min(64 * 1024, max(maxOutputBytes + 1, 1))
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destination.deallocate() }

        return try data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw ZlibError.decompressionFailed
            }
            stream.pointee.src_ptr = source
            stream.pointee.src_size = data.count

            var output = Data()
            while true {
                stream.pointee.dst_ptr = destination
                stream.pointee.dst_size = bufferSize
                let status = compression_stream_process(
                    stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.pointee.dst_size

                guard produced <= maxOutputBytes - output.count else {
                    throw ZlibError.outputTooLarge
                }
                output.append(destination, count: produced)

                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    guard produced > 0 || stream.pointee.src_size > 0 else {
                        throw ZlibError.decompressionFailed
                    }
                default:
                    throw ZlibError.decompressionFailed
                }
            }
        }
    }
}

/// base64url (RFC 4648 §5): the URL- and filename-safe base64 alphabet (`-`/`_` for
/// `+`/`/`) with padding stripped, so the share-link payload rides in a query item
/// without percent-escaping. Decoding accepts only that canonical, unpadded spelling:
/// whitespace, the standard base64 alphabet, padding, impossible lengths, and non-zero
/// unused tail bits are rejected rather than normalized into a second representation.
public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) -> Data? {
        guard
            string.utf8.allSatisfy({ byte in
                (65...90).contains(byte) || (97...122).contains(byte)
                    || (48...57).contains(byte) || byte == 45 || byte == 95
            }),
            string.utf8.count % 4 != 1
        else { return nil }

        var base64 =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore the padding base64 needs (its length must be a multiple of four).
        let remainder = base64.utf8.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        guard let decoded = Data(base64Encoded: base64) else { return nil }
        // Foundation accepts non-zero unused tail bits. Re-encoding closes that
        // ambiguity and guarantees each byte sequence has exactly one accepted token.
        guard encode(decoded) == string else { return nil }
        return decoded
    }
}
