import Darwin
import Foundation

/// Shared app/CLI output publication; rendering and filename planning stay with callers.
nonisolated public enum NonReplacingFilePublisher {
    /// Complete bytes are staged in an owned private sibling directory, then committed
    /// with one exclusive rename. A race-created output is preserved, including symlinks.
    /// Cleanup removes only the private stage; a previously published image is never undone.
    public static func publish(
        _ data: Data, to destination: URL,
        beforeCommit: (() throws -> Void)? = nil
    ) throws {
        try Task.checkCancellation()
        // Stage and commit through the same file-system representation, so the private
        // directory and the later rename name identical bytes on every volume.
        var template: [CChar] = destination.deletingLastPathComponent()
            .appendingPathComponent(".vitrine-export-XXXXXX")
            .withUnsafeFileSystemRepresentation { path in
                path.map { Array(UnsafeBufferPointer(start: $0, count: strlen($0) + 1)) } ?? []
            }
        guard !template.isEmpty else { throw POSIXError(.EINVAL) }
        guard mkdtemp(&template) != nil else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let stage = URL(
            fileURLWithFileSystemRepresentation: template, isDirectory: true, relativeTo: nil)
        defer { try? FileManager.default.removeItem(at: stage) }
        let payload = stage.appendingPathComponent("payload")
        try data.write(to: payload)
        try beforeCommit?()
        try Task.checkCancellation()
        let status: Int32 = payload.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else { return EINVAL }
                return renamex_np(source, target, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
            }
        }
        switch status {
        case 0:
            return
        case ENOTSUP, EOPNOTSUPP:
            // Some network and FAT-family volumes refuse `RENAME_EXCL`. Fall back to an
            // exclusive create, which still never replaces or follows an existing name.
            try publishByExclusiveCreate(data, to: destination)
        default:
            throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
        }
    }

    /// Non-replacing publication for volumes without exclusive rename: `O_EXCL` refuses an
    /// existing name (including a symlink, via `O_NOFOLLOW`). An I/O failure is surfaced;
    /// a partial file may remain because cleanup must not unlink a public name another
    /// process can replace. Unlike the rename path, bytes are visible while being written.
    public static func publishByExclusiveCreate(_ data: Data, to destination: URL) throws {
        try publishByExclusiveCreate(data, to: destination) { handle, bytes in
            try handle.write(contentsOf: bytes)
        }
    }

    /// A narrow fault seam for real-file error-path tests; the default writer stays public.
    static func publishByExclusiveCreate(
        _ data: Data, to destination: URL, writeContents: (FileHandle, Data) throws -> Void
    ) throws {
        let descriptor: Int32 = destination.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
            // 0o666 minus the umask matches `Data.write`, so both paths produce equal modes.
            return Darwin.open(path, flags, 0o666)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try writeContents(handle, data)
        } catch {
            try? handle.close()
            throw error
        }
        // A failed close has already released the descriptor; never close it twice,
        // because a concurrent export may have reused that descriptor number.
        try handle.close()
    }
}
