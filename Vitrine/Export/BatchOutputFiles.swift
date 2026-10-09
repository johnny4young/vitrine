import Foundation
import VitrineRendering

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

    /// Publishes through the same exclusive commit used by CLI no-clobber output.
    static func publish(
        _ data: Data, to destination: URL,
        beforeCommit: (() throws -> Void)? = nil
    ) throws {
        try NonReplacingFilePublisher.publish(data, to: destination, beforeCommit: beforeCommit)
    }

    static func publishByExclusiveCreate(_ data: Data, to destination: URL) throws {
        try NonReplacingFilePublisher.publishByExclusiveCreate(data, to: destination)
    }

    private static func key(_ filename: String) -> String {
        filename.precomposedStringWithCanonicalMapping.lowercased()
    }
}
