import Foundation
import ImageIO
import UniformTypeIdentifiers
import VitrineDomain

/// An opt-in copy of the editable project inside a saved PNG, so Vitrine can reopen the
/// image as code. The payload is the same `vitrine://open` link Copy Share Link builds,
/// stored as XMP, which ImageIO writes as a standard PNG `iTXt` chunk.
public enum EmbeddedProject {
    nonisolated static let namespace = "https://vitrineframe.app/ns/project/1.0/"
    nonisolated static let prefix = "vitrineProject"
    nonisolated static let path = "vitrineProject:link"
    /// A share link never exceeds this, so a longer value is refused before decoding.
    static let maxLinkLength = SnapshotShareLink.maxEncodedLength + 256

    public enum Withheld: Equatable, Sendable {
        /// Embedded source would undo redacted lines or blur boxes.
        case redactions
        case tooLarge
    }

    public enum Plan: Equatable {
        case off
        case embed(link: String)
        case withheld(Withheld)

        public var link: String? {
            if case .embed(let link) = self { link } else { nil }
        }
    }

    /// Decides what a save of `config` as `format` may embed. Only PNG carries a project;
    /// image content has no code of its own, so its hidden text is never embedded.
    public static func plan(
        for config: SnapshotConfig, format: ExportFormat, enabled: Bool
    ) -> Plan {
        guard enabled, format == .png, config.foregroundImage == nil else { return .off }
        if hasRedactions(config) { return .withheld(.redactions) }
        var snapshot = SharedSnapshot(capturing: config)
        if let filename = snapshot.metadata.filename, filename.contains("/") {
            snapshot.metadata.filename = (filename as NSString).lastPathComponent
        }
        guard let url = try? SnapshotShareLink.url(for: snapshot) else {
            return .withheld(.tooLarge)
        }
        return .embed(link: url.absoluteString)
    }

    static func hasRedactions(_ config: SnapshotConfig) -> Bool {
        !config.redactedLineRanges.isEmpty || config.annotations.contains { $0.kind == .blur }
    }

    /// PNG-encodes `cgImage` with `link` in its XMP. Pixels match `ExportManager.pngData`.
    nonisolated public static func pngData(from cgImage: CGImage, embedding link: String) -> Data? {
        let metadata = CGImageMetadataCreateMutable()
        guard
            CGImageMetadataRegisterNamespaceForPrefix(
                metadata, namespace as CFString, prefix as CFString, nil),
            CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, link as CFString)
        else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImageAndMetadata(destination, cgImage, metadata, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The project embedded in the PNG at `url`, or `nil` for any other file. Reads at most
    /// the image import budget and never decodes pixels.
    public static func snapshot(inPNGAt url: URL) -> SharedSnapshot? {
        guard let data = try? BackgroundImageStore.readBoundedImageData(from: url) else {
            return nil
        }
        return snapshot(inPNG: data)
    }

    /// Untrusted input: anything but a PNG with one well-formed, bounded link is `nil`.
    public static func snapshot(inPNG data: Data) -> SharedSnapshot? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard data.count <= BackgroundImageStore.maxImportBytes,
            let source = CGImageSourceCreateWithData(data as CFData, options),
            CGImageSourceGetType(source) as String? == UTType.png.identifier,
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let link = CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString)
                as String?,
            link.utf8.count <= maxLinkLength,
            let url = URL(string: link)
        else { return nil }
        return try? SnapshotShareLink.snapshot(from: url)
    }
}
