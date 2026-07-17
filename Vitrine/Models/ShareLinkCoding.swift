import Foundation

/// zlib compression for the share-link payload (analysis §14.1). A code snippet is
/// repetitive text that compresses well, keeping the encoded `vitrine://open` URL short.
/// Backed by Foundation's `NSData` compression (no third-party dependency); the
/// throwing surface lets the caller treat a corrupt payload as a malformed link rather
/// than trapping.
enum Zlib {
    enum ZlibError: Error { case compressionFailed, decompressionFailed }

    static func compress(_ data: Data) throws -> Data {
        do { return try (data as NSData).compressed(using: .zlib) as Data } catch {
            throw ZlibError.compressionFailed
        }
    }

    /// Decompresses `data`, throwing on corrupt input. `NSData.decompressed` bounds its
    /// own output, so a hostile payload cannot expand without limit here.
    static func decompress(_ data: Data) throws -> Data {
        do { return try (data as NSData).decompressed(using: .zlib) as Data } catch {
            throw ZlibError.decompressionFailed
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
