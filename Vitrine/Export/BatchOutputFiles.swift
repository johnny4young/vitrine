import Darwin
import Foundation

/// One non-replacing plan for every image and optional sidecar in a GUI batch.
nonisolated enum BatchOutputFiles {
    struct Item: Sendable {
        let image: URL
        let sidecar: URL?
    }

    static func plan(
        filenames: [String], in directory: URL, textSidecars: Bool = false
    ) throws -> [Item] {
        var occupied = Set(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).map(key))
        return try filenames.map { filename in
            guard !filename.isEmpty, !filename.contains("/"), !filename.contains("\0"),
                filename != ".", filename != ".."
            else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let requested = directory.appendingPathComponent(filename)
            let stem = requested.deletingPathExtension().lastPathComponent
            let extensionName = requested.pathExtension
            for suffix in 0..<10_000 {
                let name = suffix == 0 ? stem : "\(stem)-\(suffix + 1)"
                let image = directory.appendingPathComponent(name)
                    .appendingPathExtension(extensionName)
                let sidecar = textSidecars ? directory.appendingPathComponent(name + ".txt") : nil
                let names =
                    [image.lastPathComponent]
                    + (sidecar.map { [$0.lastPathComponent] } ?? [])
                guard names.allSatisfy({ !occupied.contains(key($0)) }) else { continue }
                occupied.formUnion(names.map(key))
                return Item(image: image, sidecar: sidecar)
            }
            throw CocoaError(.fileWriteFileExists)
        }
    }

    /// Complete bytes are staged in an owned private sibling directory, then committed
    /// with one exclusive rename. A race-created output is preserved, including symlinks.
    /// Cleanup removes only the private stage; a previously published image is never undone.
    static func publish(
        _ data: Data, to destination: URL,
        beforeCommit: (() throws -> Void)? = nil
    ) throws {
        try Task.checkCancellation()
        var template = Array(
            destination.deletingLastPathComponent()
                .appendingPathComponent(".vitrine-export-XXXXXX").path.utf8CString)
        guard mkdtemp(&template) != nil else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let pathBytes = template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let stage = URL(
            fileURLWithPath: String(decoding: pathBytes, as: UTF8.self), isDirectory: true)
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
    /// existing name (including a symlink, via `O_NOFOLLOW`), and a failed write removes
    /// only the file this call created. Unlike the rename path, the file is visible while
    /// it is written, so it is used only when the volume cannot rename exclusively.
    static func publishByExclusiveCreate(_ data: Data, to destination: URL) throws {
        let descriptor: Int32 = destination.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
            return Darwin.open(path, flags, 0o644)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
            _ = destination.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.unlink($0) }
            }
            throw error
        }
    }

    private static func key(_ filename: String) -> String {
        filename.precomposedStringWithCanonicalMapping.lowercased()
    }
}
