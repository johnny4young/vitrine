import AppKit
import Foundation
import OSLog
import Observation

/// Persists the last `limit` captures and their preview thumbnails: pinned first,
/// newest-first within each group, capped, and de-duplicated
/// by code. `UserDefaults` is injectable so it can be unit-tested.
///
/// ## Visual recents
///
/// Beyond the text list, the store keeps a small rendered PNG thumbnail for each
/// capture so the gallery can show users what a snapshot looked like — people
/// recognize an image far faster than a truncated first line of code. Thumbnails
/// are generated locally with the same renderer the app exports with, cached in a
/// private app-container directory with capped storage, and **never uploaded or
/// shared** — they are a local recognition aid only. The cache is kept in lock-step
/// with the capture list: adding a capture renders and stores its thumbnail and
/// prunes any orphans, and clearing recents clears the cache.
@MainActor
@Observable
final class RecentsStore {
    /// The shared store, constructed by the composition root (``AppEnvironment``) and
    /// reached here as a thin forwarder so existing call sites are unchanged.
    static var shared: RecentsStore { AppEnvironment.shared.recents }
    static let limit = 10

    private(set) var captures: [Capture]

    private let defaults: UserDefaults
    private let key = "recentCaptures"

    /// The local thumbnail cache backing the visual gallery.
    let thumbnails: RecentsThumbnailCache

    /// In-memory cache of decoded thumbnails, keyed by capture id. The
    /// gallery reads `thumbnail(for:)` straight from its `body`, which SwiftUI re-evaluates
    /// on every capture change *and* on window resize (the adaptive grid reflows); without
    /// this, each pass re-read and re-decoded up to `limit` PNGs from disk on the main
    /// actor. `@ObservationIgnored` keeps it a pure cache — populating it during `body`
    /// never triggers observation. Kept in lock-step with `captures` (pruned on `add`,
    /// emptied on `clear`).
    @ObservationIgnored private var decodedThumbnails: [UUID: NSImage] = [:]

    /// Renders a capture to thumbnail PNG bytes. Injectable so unit tests can drive
    /// the caching/pruning logic deterministically without invoking the real
    /// (main-actor, AppKit-backed) image renderer; the default reuses the app's
    /// export pipeline so a thumbnail looks exactly like the snapshot it previews.
    private let renderThumbnail: @MainActor (Capture) -> Data?

    init(
        defaults: UserDefaults = .standard,
        thumbnails: RecentsThumbnailCache = .container,
        renderThumbnail: @escaping @MainActor (Capture) -> Data? = RecentsThumbnail.pngData(for:)
    ) {
        self.defaults = defaults
        self.thumbnails = thumbnails
        self.renderThumbnail = renderThumbnail
        if let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Capture].self, from: data)
        {
            // Same eviction invariant as `add`: cap at `limit` by dropping the oldest
            // UNPINNED entries, but keep at least one unpinned entry — a fully-pinned
            // list legitimately persists one capture over `limit` (`add` protects the
            // newcomer), and a blunt prefix() dropped that newest capture on relaunch.
            // Pins are never evicted; a hand-inflated blob degrades to pins + 1.
            var restored = Self.ordered(decoded)
            while restored.count > Self.limit {
                let unpinned = restored.indices.filter { !restored[$0].isPinned }
                guard unpinned.count > 1, let oldest = unpinned.last else { break }
                restored.remove(at: oldest)
            }
            captures = restored
        } else {
            captures = []
        }
        // A relaunch restores the capture list from defaults but the cache lives on
        // disk independently; drop any thumbnail whose capture is no longer recent
        // so the cache cannot grow unbounded across launches.
        thumbnails.prune(keeping: Set(captures.map(\.id)))
    }

    /// Inserts `capture`, removing any existing entry with identical code, orders
    /// pins first, caps the list at `limit`, renders its thumbnail into the cache,
    /// and prunes thumbnails for any capture that fell off the list.
    func add(_ capture: Capture) {
        var capture = capture
        if captures.first(where: { $0.code == capture.code })?.isPinned == true {
            capture.isPinned = true
        }
        captures.removeAll { $0.code == capture.code }
        // Insert at the FRONT: the array's own order is then always newest-added
        // first, which is what `ordered` falls back to when dates tie — an appended
        // newcomer with a tied date would lose the tie to older entries.
        captures.insert(capture, at: 0)
        captures = Self.ordered(captures)
        while captures.count > Self.limit {
            // Evict the oldest UNPINNED capture (never the one just added). A pin is a
            // promise — "Pinned captures stay in Recents" — so when every other slot is
            // pinned there is no candidate and the list legitimately runs one over
            // `limit` instead of silently sacrificing a favorite.
            guard
                let evictionIndex = captures.indices.reversed().first(where: {
                    captures[$0].id != capture.id && !captures[$0].isPinned
                })
            else { break }
            captures.remove(at: evictionIndex)
        }
        persist()
        // The thumbnail is rendered synchronously so the gallery shows it the moment a
        // capture lands (the UX and test contract). It is small (320×200 @ 1×), and the
        // path avoids a redundant full-bitmap color copy.
        // `store(…keeping:)` reconciles the cache (caps + orphan drop) in a single
        // directory scan rather than the store-then-prune double scan.
        let keep = Set(captures.map(\.id))
        cacheThumbnail(for: capture, keeping: keep)
        // Keep the in-memory cache bounded to the live captures.
        decodedThumbnails = decodedThumbnails.filter { keep.contains($0.key) }
    }

    func clear() {
        captures.removeAll()
        decodedThumbnails.removeAll()
        persist()
        thumbnails.clear()
    }

    /// Removes every unpinned capture while preserving favorites and their cached
    /// previews. Returns the number removed so callers can distinguish a no-op
    /// without comparing store snapshots.
    @discardableResult
    func clearUnpinned() -> Int {
        let originalCount = captures.count
        captures.removeAll { !$0.isPinned }
        let removedCount = originalCount - captures.count
        guard removedCount > 0 else { return 0 }

        let keep = Set(captures.map(\.id))
        decodedThumbnails = decodedThumbnails.filter { keep.contains($0.key) }
        persist()
        thumbnails.prune(keeping: keep)
        return removedCount
    }

    /// Removes one recent capture and its cached thumbnail. Returns `false` for an
    /// unknown id so repeated or stale UI actions are harmless and do not rewrite
    /// the persisted list unnecessarily.
    @discardableResult
    func remove(id: Capture.ID) -> Bool {
        guard captures.contains(where: { $0.id == id }) else { return false }
        captures.removeAll { $0.id == id }
        decodedThumbnails[id] = nil
        persist()
        thumbnails.remove(id)
        return true
    }

    /// Pins or unpins one capture, reordering the persisted history immediately.
    /// Unknown ids are harmless so stale menus cannot mutate another capture.
    @discardableResult
    func updatePinned(id: Capture.ID, isPinned: Bool) -> Bool {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return false }
        guard captures[index].isPinned != isPinned else { return true }
        captures[index].isPinned = isPinned
        captures = Self.ordered(captures)
        persist()
        return true
    }

    /// The cached preview thumbnail for a capture, or `nil` when none is cached yet
    /// (e.g. a capture restored from an older build that predates ). Callers
    /// fall back to a placeholder so the gallery still lists the entry.
    func thumbnail(for capture: Capture) -> NSImage? {
        if let cached = decodedThumbnails[capture.id] { return cached }
        guard let image = thumbnails.image(for: capture.id) else { return nil }
        decodedThumbnails[capture.id] = image
        return image
    }

    /// Renders `capture` to a thumbnail and stores it, tolerating a render miss: a
    /// failed thumbnail just leaves the entry without a preview rather than dropping
    /// the capture. Never logs the code itself.
    private func cacheThumbnail(for capture: Capture, keeping keep: Set<UUID>) {
        guard let data = renderThumbnail(capture) else {
            Log.render.error("Recents thumbnail render produced no image")
            return
        }
        thumbnails.store(data, for: capture.id, keeping: keep)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(captures) {
            defaults.set(data, forKey: key)
        }
    }

    /// Pinned captures lead the list; each group remains newest-first. Ties on the
    /// date fall back to the array's own order — a STABLE sort — not a UUID
    /// comparison: captures added in the same instant carry equal dates (a coarse
    /// clock tick on the CI runner grouped the demo seed's three), and a random-UUID
    /// tie-break ordered them differently from run to run. `add` inserts at the
    /// front, so the array is always newest-added first and stability preserves
    /// insertion recency; stability also makes this idempotent, which matters because
    /// `add`/`updatePinned` re-run it over an already-ordered array.
    private static func ordered(_ captures: [Capture]) -> [Capture] {
        captures.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned { return lhs.element.isPinned }
                if lhs.element.date != rhs.element.date {
                    return lhs.element.date > rhs.element.date
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

// MARK: - Thumbnail rendering

/// Renders a `Capture` to a small preview PNG using the app's own export pipeline,
/// so a gallery thumbnail is a faithful (if tiny) version of the real snapshot.
///
/// The render runs entirely on-device through `ExportManager`/`SnapshotCanvas`; it
/// pins a fixed logical size so every thumbnail has predictable, bounded
/// dimensions (and therefore a bounded byte size). No network, screen recording,
/// or accessibility permission is involved, and nothing leaves the machine.
enum RecentsThumbnail {
    /// The logical size every thumbnail is rendered at. Small enough to keep the
    /// cache tiny, large enough to recognize the theme, language, and code shape.
    static let size = CGSize(width: 320, height: 200)

    /// PNG bytes for `capture`'s preview, or `nil` if the render fails.
    @MainActor
    static func pngData(for capture: Capture) -> Data? {
        let config = capture.applying(to: SnapshotConfig())
        // Thumbnails are recognition aids, not exports: render at 1× into the fixed
        // frame so the cached file stays small and uniform.
        guard let cgImage = ExportManager.renderCGImage(config, scale: 1, fixedSize: size) else {
            return nil
        }
        return ExportManager.pngData(from: cgImage)
    }
}

// MARK: - Thumbnail cache

/// Stores capture preview thumbnails inside the app container with capped storage.
///
/// Vitrine never uploads a thumbnail and never asks for a broad file entitlement:
/// thumbnails are PNGs the app renders itself and writes into a private directory
/// under Application Support, named by the capture's UUID. The cache is bounded two
/// ways so it can never grow without limit:
///
/// - **Count cap** — at most `maxEntries` files are kept; the oldest files (by
///   modification date) are evicted first.
/// - **Byte cap** — the total on-disk size is kept under `maxTotalBytes`, again
///   evicting oldest-first.
///
/// `prune(keeping:)` additionally drops any file whose capture is no longer in the
/// recents list, so the cache tracks the (already capped) capture history. The base
/// directory is injectable so the store/eviction behavior is unit-testable without
/// touching the real container.
struct RecentsThumbnailCache {
    /// The directory holding the cached thumbnail PNGs. Created on demand.
    let directory: URL

    /// The maximum number of thumbnails kept on disk. Defaults to the recents
    /// `limit` so the cache and the capture list stay the same size.
    let maxEntries: Int

    /// The maximum total bytes the cache may occupy on disk. A small budget, since
    /// each thumbnail is a tiny fixed-size PNG.
    let maxTotalBytes: Int

    init(
        directory: URL,
        maxEntries: Int = RecentsStore.limit,
        maxTotalBytes: Int = 8 * 1024 * 1024
    ) {
        self.directory = directory
        self.maxEntries = maxEntries
        self.maxTotalBytes = maxTotalBytes
    }

    /// The cache rooted at the app's Application Support container — the path used
    /// in the running app. Falls back to a temporary directory if Application
    /// Support is somehow unavailable, so the cache is always usable.
    static var container: RecentsThumbnailCache {
        let base =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return RecentsThumbnailCache(
            directory: base.appendingPathComponent("Recents/Thumbnails", isDirectory: true))
    }

    /// Writes thumbnail `data` for `id`, then enforces the count and byte caps. A
    /// write failure is non-fatal — the capture simply has no cached preview.
    func store(_ data: Data, for id: UUID) {
        guard write(data, for: id) else { return }
        enforceCaps()
    }

    /// Writes thumbnail `data` for `id`, then reconciles the cache (orphan drop + caps)
    /// against the live capture ids in a **single** directory scan, for the hot `add`
    /// path that would otherwise scan twice — store-then-prune.
    func store(_ data: Data, for id: UUID, keeping keep: Set<UUID>) {
        guard write(data, for: id) else { return }
        reconcile(keeping: keep)
    }

    /// Writes thumbnail bytes for `id`, creating the directory. Returns whether the write
    /// succeeded; a failure is non-fatal (the entry just renders without a preview).
    @discardableResult
    private func write(_ data: Data, for id: UUID) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: id), options: .atomic)
            return true
        } catch {
            Log.render.error("Recents thumbnail write failed; entry will have no preview")
            return false
        }
    }

    /// Resolves the on-disk URL for `id`'s thumbnail, or `nil` when none is cached.
    func url(for id: UUID) -> URL? {
        let candidate = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    /// Loads `id`'s cached thumbnail as an image, or `nil` if absent/undecodable.
    /// `NSImage(contentsOf:)` already yields `nil` for a missing file, so no separate
    /// `fileExists` stat is needed.
    func image(for id: UUID) -> NSImage? {
        NSImage(contentsOf: fileURL(for: id))
    }

    /// Number of thumbnails currently cached. Exposed for tests and diagnostics.
    var count: Int { cachedFiles().count }

    /// Total bytes the cache currently occupies on disk. Exposed for tests.
    var totalBytes: Int { cachedFiles().reduce(0) { $0 + $1.size } }

    /// Removes every cached thumbnail whose id is **not** in `keep`, so the cache
    /// follows the capture list as entries fall off the end.
    func prune(keeping keep: Set<UUID>) {
        for file in cachedFiles() where !keep.contains(file.id) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    /// Removes a single capture's thumbnail (e.g. an individual recents deletion).
    func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// Deletes every cached thumbnail (used by "Clear Recents").
    func clear() {
        for file in cachedFiles() {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - Internals

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png", isDirectory: false)
    }

    /// A cached thumbnail file with the metadata eviction needs.
    private struct CachedFile {
        let url: URL
        let id: UUID
        let size: Int
        let modified: Date
    }

    /// Enumerates the cache directory's thumbnail files, newest first. A missing
    /// directory (nothing cached yet) yields an empty list rather than throwing.
    private func cachedFiles() -> [CachedFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles])
        else { return [] }
        return
            urls
            .filter { $0.pathExtension == "png" }
            .compactMap { url -> CachedFile? in
                // Only count files whose name is a real capture UUID, so a stray
                // file can never be mistaken for a thumbnail.
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
                else { return nil }
                let values = try? url.resourceValues(forKeys: Set(keys))
                return CachedFile(
                    url: url,
                    id: id,
                    size: values?.fileSize ?? 0,
                    modified: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Evicts oldest-first until the cache is within both the count and byte caps.
    private func enforceCaps() {
        _ = evictToCaps(cachedFiles())
    }

    /// Drops thumbnails whose id is not in `keep`, then enforces the caps — all from a
    /// single directory scan, so the hot `add` path reconciles in one pass.
    /// Caps are applied before the orphan drop, matching the prior store-then-prune order.
    private func reconcile(keeping keep: Set<UUID>) {
        // The count cap floors at the live capture set: with every slot pinned the
        // store legitimately runs past `limit`, and a fixed cap would evict a live
        // (pinned) capture's thumbnail by age.
        let survivors = evictToCaps(cachedFiles(), countCap: max(maxEntries, keep.count))
        for file in survivors where !keep.contains(file.id) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    /// Evicts oldest-first from `files` (newest first) until within both the count and
    /// byte caps, and returns the survivors. Shared by `enforceCaps` and `reconcile` so
    /// the eviction policy lives in one place.
    @discardableResult
    private func evictToCaps(_ files: [CachedFile], countCap: Int? = nil) -> [CachedFile] {
        var files = files  // newest first
        let cap = countCap ?? maxEntries

        // Count cap: drop everything past the newest `cap`.
        if files.count > cap {
            for file in files[cap...] {
                try? FileManager.default.removeItem(at: file.url)
            }
            files = Array(files.prefix(cap))
        }

        // Byte cap: while over budget, evict the oldest (last) entry.
        var total = files.reduce(0) { $0 + $1.size }
        while total > maxTotalBytes, let oldest = files.last {
            try? FileManager.default.removeItem(at: oldest.url)
            total -= oldest.size
            files.removeLast()
        }
        return files
    }
}
