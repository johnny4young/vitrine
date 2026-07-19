import Compression
import Foundation

/// zlib compression for the share-link payload. A code snippet is repetitive text that
/// compresses well, keeping the encoded `vitrine://open` URL short.
/// Backed by Foundation's `NSData` compression (no third-party dependency); the
/// throwing surface lets the caller treat a corrupt payload as a malformed link rather
/// than trapping.
enum Zlib {
    enum ZlibError: Error, Equatable {
        case compressionFailed
        case decompressionFailed
        case outputTooLarge
    }

    static func compress(_ data: Data) throws -> Data {
        do { return try (data as NSData).compressed(using: .zlib) as Data } catch {
            throw ZlibError.compressionFailed
        }
    }

    /// Decompresses `data` with a caller-provided output ceiling. The stream is stopped
    /// as soon as the next chunk would cross the limit, before a compressed payload can
    /// expand into an unbounded allocation.
    static func decompress(_ data: Data, maxOutputBytes: Int) throws -> Data {
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
/// without percent-escaping. `decode` is tolerant of a re-padded or whitespace-wrapped
/// string and returns `nil` on anything that is not valid base64url.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 =
            string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Restore the padding base64 needs (its length must be a multiple of four).
        let remainder = base64.count % 4
        if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }
}
