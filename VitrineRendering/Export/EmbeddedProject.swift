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
    /// Above the share link's 64 KB encoded limit, so only crafted values are refused here.
    nonisolated static let maxLinkLength = 64 * 1024 + 256
    nonisolated static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    public enum Withheld: Equatable, Sendable {
        case redactedLines
        case blurBoxes
        /// The raw stream holds scrollback and redraws the image never shows.
        case terminal
        case secret
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
        if config.language == .terminal { return .withheld(.terminal) }
        if !config.redactedLineRanges.isEmpty { return .withheld(.redactedLines) }
        if config.annotations.contains(where: { $0.kind == .blur }) {
            return .withheld(.blurBoxes)
        }
        var embedded = config
        // A hidden window bar draws no title, so the image must not carry one either.
        if !config.showChrome { embedded.windowTitle = "" }
        embedded.metadata.filename = config.metadata.filename.map(strippingPath)
        // Unlike the image, a project can't be redacted after the fact, so any finding blocks it.
        guard ExportPreflight(embedded, payload: .transcript).isClean else {
            return .withheld(.secret)
        }
        guard let url = try? SnapshotShareLink.url(for: SharedSnapshot(capturing: embedded))
        else { return .withheld(.tooLarge) }
        return .embed(link: url.absoluteString)
    }

    /// Reduces a filesystem path to its file name; any other header text, such as
    /// `app · feature/login`, is kept as typed.
    static func strippingPath(_ text: String) -> String {
        if text.hasPrefix("file://"), let url = URL(string: text), url.isFileURL {
            return url.lastPathComponent
        }
        guard text.hasPrefix("/") || text.hasPrefix("~/") else { return text }
        return (text as NSString).lastPathComponent
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

    /// The project embedded in the PNG at `url`, or `nil` for any other file. Any other
    /// format costs one 8-byte read; a PNG is parsed off the main actor without decoding pixels.
    public static func snapshot(inPNGAt url: URL) async -> SharedSnapshot? {
        guard let link = await link(inPNGAt: url) else { return nil }
        return decode(link)
    }

    /// Untrusted input: anything but a PNG with one well-formed, bounded link is `nil`.
    public static func snapshot(inPNG data: Data) -> SharedSnapshot? {
        link(inPNG: data).flatMap(decode)
    }

    @concurrent
    nonisolated static func link(inPNGAt url: URL) async -> String? {
        guard hasPNGSignature(at: url),
            let data = try? BackgroundImageStore.readBoundedImageData(from: url)
        else { return nil }
        return link(inPNG: data)
    }

    nonisolated static func hasPNGSignature(at url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
            let handle = try? FileHandle(forReadingFrom: url)
        else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: pngSignature.count)).map([UInt8].init) == pngSignature
    }

    nonisolated static func link(inPNG data: Data) -> String? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard data.count <= BackgroundImageStore.maxImportBytes,
            data.starts(with: pngSignature),
            let source = CGImageSourceCreateWithData(data as CFData, options),
            CGImageSourceGetType(source) as String? == UTType.png.identifier,
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
            let link = CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString)
                as String?,
            link.utf8.count <= maxLinkLength
        else { return nil }
        return link
    }

    static func decode(_ link: String) -> SharedSnapshot? {
        URL(string: link).flatMap { try? SnapshotShareLink.snapshot(from: $0) }
    }
}
