import Darwin
import Foundation

/// Reads one regular-file descriptor without retaining more than `limit + 1` bytes.
/// Rejects observed size, modification-time or change-time changes during the read.
/// Metadata checks do not guarantee a snapshot against arbitrary uncooperative writers.
/// Change time also moves for metadata-only events (extended attributes, permissions),
/// so a read racing one of those fails closed as `unreadable`; callers may simply retry.
/// Cancellation between chunks surfaces as `CancellationError`, never as a read error.
///
/// Callers remain responsible for security-scoped access and for translating these
/// transport errors into their domain-specific messages. Opening with `O_NONBLOCK`
/// prevents a path swap to a FIFO from hanging the app, while both type and stability
/// checks use `fstat` on the descriptor that is actually read rather than re-statting
/// the pathname.
public enum BoundedFileReader {
    public enum ReadError: Error, Equatable {
        case unreadable
        case notRegularFile
        case tooLarge
    }

    private static let chunkByteCount = 64 * 1024

    public static func read(from url: URL, limit: Int) throws -> Data {
        try read(from: url, limit: limit, afterChunk: nil)
    }

    /// Internal observer lets descriptor interleavings be tested without timing or live files.
    static func read(
        from url: URL,
        limit: Int,
        afterChunk: ((Int) throws -> Void)?
    ) throws -> Data {
        try Task.checkCancellation()
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
                try Task.checkCancellation()
                let remaining = retainedByteCount - data.count
                let requestByteCount = min(chunkByteCount, remaining)
                guard
                    let chunk = try handle.read(upToCount: requestByteCount),
                    !chunk.isEmpty
                else {
                    break
                }
                data.append(chunk)
                try afterChunk?(data.count)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ReadError.unreadable
        }

        try Task.checkCancellation()
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
        try validateChangeEvidence(initial: initialStatus, final: finalStatus)
        return data
    }

    static func validateChangeEvidence(initial: stat, final: stat) throws {
        guard
            initial.st_mtimespec.tv_sec == final.st_mtimespec.tv_sec,
            initial.st_mtimespec.tv_nsec == final.st_mtimespec.tv_nsec,
            initial.st_ctimespec.tv_sec == final.st_ctimespec.tv_sec,
            initial.st_ctimespec.tv_nsec == final.st_ctimespec.tv_nsec
        else {
            throw ReadError.unreadable
        }
    }

    private static func isRegular(_ status: stat) -> Bool {
        status.st_mode & S_IFMT == S_IFREG
    }

    /// Keeps the race policy pure and directly testable. Growth is classified as
    /// `tooLarge` even below the nominal limit because the reader intentionally
    /// refuses timing-dependent input; shrinking/replacement is `unreadable`.
    public static func validateStableRead(
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
