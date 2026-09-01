import Darwin
import Foundation

/// Reads one stable regular-file descriptor without retaining more than `limit + 1` bytes.
///
/// Callers remain responsible for security-scoped access and for translating these
/// transport errors into their domain-specific messages. Opening with `O_NONBLOCK`
/// prevents a path swap to a FIFO from hanging the app, while both type and stability
/// checks use `fstat` on the descriptor that is actually read rather than re-statting
/// the pathname.
nonisolated enum BoundedFileReader {
    enum ReadError: Error, Equatable {
        case unreadable
        case notRegularFile
        case tooLarge
    }

    private static let chunkByteCount = 64 * 1024

    static func read(from url: URL, limit: Int) throws -> Data {
        guard limit >= 0, limit < Int.max else { throw ReadError.unreadable }

        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw ReadError.unreadable }

        var initialStatus = stat()
        guard fstat(descriptor, &initialStatus) == 0 else {
            Darwin.close(descriptor)
            throw ReadError.unreadable
        }
        guard Self.isRegular(initialStatus) else {
            Darwin.close(descriptor)
            throw ReadError.notRegularFile
        }
        guard
            let initialByteCount = Int(exactly: initialStatus.st_size),
            initialByteCount >= 0
        else {
            Darwin.close(descriptor)
            throw ReadError.unreadable
        }
        guard initialByteCount <= limit else {
            Darwin.close(descriptor)
            throw ReadError.tooLarge
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
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

        var finalStatus = stat()
        guard fstat(descriptor, &finalStatus) == 0 else { throw ReadError.unreadable }
        guard Self.isRegular(finalStatus) else { throw ReadError.notRegularFile }
        guard
            initialStatus.st_dev == finalStatus.st_dev,
            initialStatus.st_ino == finalStatus.st_ino,
            let finalByteCount = Int(exactly: finalStatus.st_size),
            finalByteCount >= 0
        else {
            throw ReadError.unreadable
        }

        try validateStableRead(
            initialByteCount: initialByteCount,
            finalByteCount: finalByteCount,
            readByteCount: data.count)
        return data
    }

    private static func isRegular(_ status: stat) -> Bool {
        status.st_mode & S_IFMT == S_IFREG
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
