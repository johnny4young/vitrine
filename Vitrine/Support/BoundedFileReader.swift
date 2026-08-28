import Foundation

/// Reads a stable regular file without ever retaining more than `limit + 1` bytes.
///
/// Callers remain responsible for security-scoped access and for translating these
/// transport errors into their domain-specific messages. The reader deliberately
/// avoids `Data(contentsOf:)`: a metadata preflight alone is racy because a file can
/// be replaced or grow between the size check and the read.
enum BoundedFileReader {
    enum ReadError: Error, Equatable {
        case unreadable
        case notRegularFile
        case tooLarge
    }

    private static let chunkByteCount = 64 * 1024

    static func read(from url: URL, limit: Int) throws -> Data {
        guard limit >= 0, limit < Int.max else { throw ReadError.unreadable }

        let initialValues = try resourceValues(for: url)
        guard initialValues.isRegularFile == true else { throw ReadError.notRegularFile }
        guard let initialByteCount = initialValues.fileSize, initialByteCount >= 0 else {
            throw ReadError.unreadable
        }
        guard initialByteCount <= limit else { throw ReadError.tooLarge }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ReadError.unreadable
        }
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(initialByteCount)
        let retainedByteCount = limit + 1

        do {
            while data.count < retainedByteCount {
                let remaining = retainedByteCount - data.count
                let requestByteCount = min(chunkByteCount, remaining)
                guard
                    let chunk = try handle.read(upToCount: requestByteCount),
                    !chunk.isEmpty
                else {
                    break
                }
                data.append(chunk)
            }
        } catch {
            throw ReadError.unreadable
        }

        guard data.count <= limit else { throw ReadError.tooLarge }

        let finalValues = try resourceValues(for: url)
        guard finalValues.isRegularFile == true else { throw ReadError.notRegularFile }
        guard let finalByteCount = finalValues.fileSize, finalByteCount >= 0 else {
            throw ReadError.unreadable
        }

        try validateStableRead(
            initialByteCount: initialByteCount,
            finalByteCount: finalByteCount,
            readByteCount: data.count)

        return data
    }

    private static func resourceValues(for url: URL) throws -> URLResourceValues {
        do {
            return try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw ReadError.unreadable
        }
    }

    /// Keeps the race policy pure and directly testable. Growth is classified as
    /// `tooLarge` even below the nominal limit because the reader intentionally
    /// refuses timing-dependent input; shrinking/replacement is `unreadable`.
    static func validateStableRead(
        initialByteCount: Int,
        finalByteCount: Int,
        readByteCount: Int
    ) throws {
        guard finalByteCount <= initialByteCount, readByteCount <= initialByteCount else {
            throw ReadError.tooLarge
        }
        guard finalByteCount == initialByteCount, readByteCount == initialByteCount else {
            throw ReadError.unreadable
        }
    }
}
