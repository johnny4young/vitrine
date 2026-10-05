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
        let result = payload.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in
                guard let source, let target else { return Int32(-1) }
                return renamex_np(source, target, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func key(_ filename: String) -> String {
        filename.precomposedStringWithCanonicalMapping.lowercased()
    }
}
