import AppKit
import OSLog
import SwiftUI

/// The user's brand identity — a logo, a handle, an optional project label, an
/// accent color, and a corner placement — applied as a watermark to exported
/// snapshots (the PRO Brand Kit).
///
/// One brand kit is shared app-wide (like the working social card), persisted as a
/// JSON blob and resolved into a render-ready `Watermark` by `BrandKitStore`. Text
/// fields are normalized (trimmed) on the way in, and decoding re-normalizes, so a
/// hand-edited or corrupt store can never feed stray whitespace into the layout
/// (defensive posture).
struct BrandKit: Equatable, Codable {
    /// The logo image, stored in the app container and referenced by name
    /// (`BackgroundImageStore`). `nil` for a text-only mark.
    var logo: ImageReference?

    /// The handle shown in the mark, e.g. `@jane`. Normalized; may be empty.
    var handle: String

    /// The project/repository label, e.g. `vitrine`. Normalized; may be empty.
    var project: String

    /// The link the QR chip encodes (a profile/repo/article URL), or empty for no
    /// chip. Normalized; rendered fully on-device.
    var linkURL: String

    /// The accent tint for the mark's text, or `nil` to use the legible default.
    var accent: RGBAColor?

    /// Which corner the mark sits in — or `.free`, where `freePosition` places it.
    var placement: Watermark.Placement

    /// For `.free` placement: the mark's center as a normalized point in the canvas
    /// (x,y in 0…1), set by dragging it in a preview. Ignored for the corners.
    var freePosition: CGPoint

    init(
        logo: ImageReference? = nil,
        handle: String = "",
        project: String = "",
        linkURL: String = "",
        accent: RGBAColor? = nil,
        placement: Watermark.Placement = .bottomTrailing,
        freePosition: CGPoint = CGPoint(x: 0.84, y: 0.9)
    ) {
        self.logo = logo
        self.handle = Self.normalized(handle)
        self.project = Self.normalized(project)
        self.linkURL = Self.normalized(linkURL)
        self.accent = accent
        self.placement = placement
        self.freePosition = Watermark.clampFreePosition(freePosition)
    }

    /// Trims surrounding whitespace/newlines so a blank field never reserves layout
    /// space in the mark.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the kit carries anything to draw — a logo, a non-empty line, or a
    /// QR link.
    var hasContent: Bool {
        logo != nil || !handle.isEmpty || !project.isEmpty || !linkURL.isEmpty
    }

    /// The composed `handle · project` line for the watermark (either part may be
    /// absent), or an empty string when both are blank.
    var watermarkText: String {
        [handle, project].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case logo, handle, project, linkURL, accent, placement, freePosition
    }

    /// Decodes tolerantly and re-normalizes, so a corrupt blob degrades to a clean
    /// default rather than feeding bad data into the mark.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            logo: try? container.decodeIfPresent(ImageReference.self, forKey: .logo),
            handle: (try? container.decodeIfPresent(String.self, forKey: .handle)) ?? "",
            project: (try? container.decodeIfPresent(String.self, forKey: .project)) ?? "",
            linkURL: (try? container.decodeIfPresent(String.self, forKey: .linkURL)) ?? "",
            accent: try? container.decodeIfPresent(RGBAColor.self, forKey: .accent),
            placement: (try? container.decodeIfPresent(Watermark.Placement.self, forKey: .placement))
                ?? .bottomTrailing,
            freePosition: (try? container.decodeIfPresent(CGPoint.self, forKey: .freePosition))
                ?? CGPoint(x: 0.84, y: 0.9)
        )
    }
}

/// Owns the app-wide brand kit and the "apply to captures" switch, and resolves the
/// kit into a render-ready `Watermark`.
///
/// Mirrors `PresetStore`/`CustomThemeStore`: a single shared instance backed by the
/// app's resolved defaults, with `UserDefaults` (and the logo image store)
/// injectable so the whole thing is unit-testable without touching the real
/// container. The kit persists as one JSON blob; the logo is copied into the
/// container through the same content-addressed `BackgroundImageStore` the
/// backgrounds use, so only an in-container file name is stored.
///
/// The resolver is the single gate: it returns `nil` — no watermark — unless the
/// user enabled it, PRO is unlocked, and the kit actually has content. So the brand
/// kit can be configured for free, but it only marks an export once PRO is active,
/// and it is the caller's `isPro` (read from `Entitlements`) that decides.
@MainActor
@Observable
final class BrandKitStore {
    /// The shared store, constructed by the composition root (``AppEnvironment``) and
    /// reached here as a thin forwarder so existing call sites are unchanged.
    static var shared: BrandKitStore { AppEnvironment.shared.brandKit }

    /// Persisted key names. Exposed so the central settings reset/schema registry
    /// clears Brand Kit alongside every other user preference.
    static let storageKey = "brandKit"
    static let enabledStorageKey = "brandKitEnabled"

    /// The working brand kit. Persisted on change; the logo cache is refreshed so
    /// the resolver stays fast and free of disk reads in the render path.
    var brandKit: BrandKit {
        didSet {
            guard !isReloading else {
                refreshLogoCache()
                refreshQRCache(previousLink: nil)
                return
            }
            persist()
            refreshLogoCache()
            refreshQRCache(previousLink: oldValue.linkURL)
        }
    }

    /// Whether the brand kit is applied to captures. Off by default, so a
    /// fresh install (and the golden suite) renders unbranded until the user opts in.
    var isEnabled: Bool {
        didSet {
            guard !isReloading else { return }
            defaults.set(isEnabled, forKey: Keys.enabled)
        }
    }

    private let defaults: UserDefaults
    private let imageStore: BackgroundImageStore

    /// The decoded logo bytes, cached so `resolvedWatermark` does no disk I/O on the
    /// render/preview hot path. Refreshed whenever the logo changes.
    private var cachedLogoData: Data?

    /// The decoded logo image, cached so the Settings preview doesn't re-read and re-decode
    /// the file from disk on every SwiftUI body pass.
    private var cachedLogoImage: NSImage?

    /// The generated QR chip for `brandKit.linkURL`, cached so `resolvedWatermark`
    /// never runs the Core Image filter on the render/preview hot path.
    /// Regenerated only when the link actually changes.
    private var cachedQRImage: NSImage?

    /// Suppresses write-back while `reload()` mirrors an external reset into memory.
    private var isReloading = false

    private enum Keys {
        static let kit = BrandKitStore.storageKey
        static let enabled = BrandKitStore.enabledStorageKey
    }

    init(defaults: UserDefaults = .standard, imageStore: BackgroundImageStore = .container) {
        self.defaults = defaults
        self.imageStore = imageStore
        self.brandKit = Self.read(from: defaults)
        self.isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        refreshLogoCache()
        refreshQRCache(previousLink: nil)
    }

    /// The render-ready watermark, or `nil` when the kit is disabled, PRO is locked,
    /// or there is nothing to draw. This is the only path that turns a brand
    /// kit into a rendered mark, so a free or empty build never watermarks an export.
    func resolvedWatermark(isPro: Bool) -> Watermark? {
        guard isEnabled, isPro else { return nil }
        let text = brandKit.watermarkText
        guard cachedLogoData != nil || !text.isEmpty || cachedQRImage != nil else { return nil }
        return Watermark(
            text: text,
            logoImageData: cachedLogoData,
            logoImage: cachedLogoImage,
            logoIdentity: brandKit.logo?.fileName,
            tint: brandKit.accent,
            placement: brandKit.placement,
            freePosition: brandKit.freePosition,
            qrImage: cachedQRImage,
            qrIdentity: brandKit.linkURL.isEmpty ? nil : brandKit.linkURL)
    }

    /// Imports a user-picked logo file into the container and adopts it, returning
    /// whether it succeeded. The file is validated as an image and copied under a
    /// content-addressed name, exactly like a background image.
    @discardableResult
    func importLogo(from url: URL) -> Bool {
        do {
            brandKit.logo = try imageStore.importImage(from: url)
            Log.export.info("Imported a brand-kit logo")
            return true
        } catch {
            Log.export.error("Brand-kit logo import failed")
            return false
        }
    }

    /// Clears the logo, leaving the rest of the kit intact.
    func removeLogo() { brandKit.logo = nil }

    /// The resolved logo image for the Settings preview (cached; see `cachedLogoImage`).
    var logoImage: NSImage? { cachedLogoImage }

    /// Re-reads the kit from the backing store (used after an external reset).
    func reload() {
        isReloading = true
        defer { isReloading = false }
        brandKit = Self.read(from: defaults)
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
    }

    /// Regenerates the QR chip when the link changed (or on init/reload, where
    /// `previousLink` is nil and the cache must be rebuilt unconditionally).
    private func refreshQRCache(previousLink: String?) {
        if let previousLink, previousLink == brandKit.linkURL { return }
        cachedQRImage = QRCodeGenerator.image(for: brandKit.linkURL).map { cg in
            NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    private func refreshLogoCache() {
        cachedLogoData = brandKit.logo.flatMap { reference in
            imageStore.url(for: reference).flatMap { try? Data(contentsOf: $0) }
        }
        cachedLogoImage = cachedLogoData.flatMap { NSImage(data: $0) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(brandKit) else { return }
        defaults.set(data, forKey: Keys.kit)
    }

    private static func read(from defaults: UserDefaults) -> BrandKit {
        guard let data = defaults.data(forKey: Keys.kit),
            let kit = try? JSONDecoder().decode(BrandKit.self, from: data)
        else { return BrandKit() }
        return kit
    }
}
