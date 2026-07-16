import AppKit
import Foundation
import Testing

@testable import Vitrine

/// CS-013 / CS-029 — the recents store, its capped on-disk thumbnail cache, and
/// the thumbnail renderer that backs the visual gallery.
///
/// The cache tests drive a temporary directory and inject a deterministic
/// `renderThumbnail` closure so the count/byte-cap and pruning logic is exercised
/// without invoking the real (AppKit-backed) image renderer. A single separate
/// smoke test does run the real renderer to prove a capture produces decodable PNG
/// bytes.
@MainActor
@Suite("RecentsStore")
struct RecentsStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "VitrineRecents-\(UUID().uuidString)")!
    }

    /// A fresh, isolated cache directory under the temp dir, removed when the
    /// returned cleanup closure runs.
    private func tempCache(
        maxEntries: Int = RecentsStore.limit,
        maxTotalBytes: Int = 8 * 1024 * 1024
    ) -> (cache: RecentsThumbnailCache, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VitrineRecentsTests-\(UUID().uuidString)", isDirectory: true)
        let cache = RecentsThumbnailCache(
            directory: directory, maxEntries: maxEntries, maxTotalBytes: maxTotalBytes)
        return (cache, { try? FileManager.default.removeItem(at: directory) })
    }

    /// `count` bytes of deterministic, non-empty thumbnail stand-in data.
    private func fakeThumbnail(bytes count: Int) -> Data {
        Data(repeating: 0xAB, count: max(1, count))
    }

    private func capture(_ code: String) -> Capture {
        Capture(code: code, languageID: "swift", themeID: "one-dark")
    }

    // MARK: - List behavior (CS-013)

    @Test func capsDedupesNewestFirst() {
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })

        for index in 0..<15 {
            store.add(capture("code \(index)"))
        }
        #expect(store.captures.count == RecentsStore.limit)
        #expect(store.captures.first?.code == "code 14")

        store.add(capture("code 14"))
        #expect(store.captures.count == RecentsStore.limit)
        #expect(store.captures.filter { $0.code == "code 14" }.count == 1)
    }

    @Test func persistsToDefaults() {
        let defaults = freshDefaults()
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        RecentsStore(
            defaults: defaults, thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) }
        )
        .add(capture("hello"))

        let reloaded = RecentsStore(
            defaults: defaults, thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })
        #expect(reloaded.captures.first?.code == "hello")
    }

    // MARK: - Cache lock-step with the list (CS-029)

    @Test func addCachesThumbnailForEachCapture() {
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })

        let first = capture("let x = 1")
        store.add(first)
        #expect(store.thumbnail(for: first) != nil || cache.url(for: first.id) != nil)
        #expect(cache.count == 1)
    }

    @Test func cacheNeverExceedsCountCap() {
        // Cache count cap defaults to the recents limit, so adding far more
        // captures than the limit must still leave at most `limit` files on disk.
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })

        for index in 0..<(RecentsStore.limit * 3) {
            store.add(capture("snippet \(index)"))
        }
        #expect(store.captures.count == RecentsStore.limit)
        #expect(cache.count <= RecentsStore.limit)
    }

    @Test func clearEmptiesListAndCache() {
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })

        store.add(capture("a"))
        store.add(capture("b"))
        #expect(cache.count > 0)

        store.clear()
        #expect(store.captures.isEmpty)
        #expect(cache.count == 0)
    }

    @Test func removeDeletesOnlyTheRequestedCaptureAndThumbnail() {
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })
        let kept = capture("keep")
        let removed = capture("remove")
        store.add(kept)
        store.add(removed)

        #expect(store.remove(id: removed.id))
        #expect(store.captures.map(\.id) == [kept.id])
        #expect(cache.url(for: removed.id) == nil)
        #expect(cache.url(for: kept.id) != nil)
        #expect(!store.remove(id: removed.id))
    }

    @Test func restorePrunesOrphanThumbnails() {
        // A relaunch restores the capture list from defaults but the cache lives on
        // disk independently; a thumbnail whose capture is no longer recent must be
        // pruned at init so the cache cannot grow unbounded across launches.
        let defaults = freshDefaults()
        let (cache, cleanup) = tempCache()
        defer { cleanup() }

        let kept = capture("kept")
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })
        store.add(kept)

        // Write a stray thumbnail for a capture that is not in the list.
        let orphanID = UUID()
        cache.store(fakeThumbnail(bytes: 64), for: orphanID)
        #expect(cache.url(for: orphanID) != nil)

        // Re-create the store from the same defaults + cache: init should prune the
        // orphan but keep the live capture's thumbnail.
        _ = RecentsStore(
            defaults: defaults, thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })
        #expect(cache.url(for: orphanID) == nil)
        #expect(cache.url(for: kept.id) != nil)
    }

    @Test func reAddingIdenticalCodeReplacesItsThumbnailWithoutOrphaning() {
        // Re-adding identical code de-dupes the list entry but mints a *new* capture
        // id, so the previous id's thumbnail becomes an orphan. The store's lock-step
        // pruning must drop that orphan and leave exactly one cached thumbnail — under
        // the new id — for the deduped code (CS-013/CS-029).
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache,
            renderThumbnail: { [self] _ in fakeThumbnail(bytes: 64) })

        let original = capture("let answer = 42")
        store.add(original)
        #expect(cache.url(for: original.id) != nil)

        let readded = capture("let answer = 42")
        store.add(readded)

        // List de-duped to a single entry under the new id.
        #expect(store.captures.count == 1)
        #expect(store.captures.first?.id == readded.id)
        // Cache followed: exactly one thumbnail, the original id pruned as an orphan.
        #expect(cache.count == 1)
        #expect(cache.url(for: original.id) == nil)
        #expect(cache.url(for: readded.id) != nil)
    }

    // MARK: - Cache caps in isolation (CS-029)

    @Test func cacheEvictsOldestPastCountCap() {
        let (cache, cleanup) = tempCache(maxEntries: 3)
        defer { cleanup() }

        var ids: [UUID] = []
        for _ in 0..<5 {
            let id = UUID()
            ids.append(id)
            cache.store(fakeThumbnail(bytes: 128), for: id)
        }

        #expect(cache.count == 3)
        // The three most recent writes survive; the two oldest are evicted.
        #expect(cache.url(for: ids[0]) == nil)
        #expect(cache.url(for: ids[1]) == nil)
        #expect(cache.url(for: ids[4]) != nil)
    }

    @Test func cacheEvictsOldestPastByteCap() {
        // Budget for ~2 thumbnails; a third write must evict back under budget.
        let perThumbnail = 4096
        let (cache, cleanup) = tempCache(maxEntries: 100, maxTotalBytes: perThumbnail * 2 + 1)
        defer { cleanup() }

        var ids: [UUID] = []
        for _ in 0..<4 {
            let id = UUID()
            ids.append(id)
            cache.store(fakeThumbnail(bytes: perThumbnail), for: id)
        }

        #expect(cache.totalBytes <= perThumbnail * 2 + 1)
        #expect(cache.count <= 2)
        // Newest survives, oldest evicted.
        #expect(cache.url(for: ids.last!) != nil)
        #expect(cache.url(for: ids.first!) == nil)
    }

    @Test func pruneKeepsOnlyListedIDs() {
        let (cache, cleanup) = tempCache()
        defer { cleanup() }

        let keepID = UUID()
        let dropID = UUID()
        cache.store(fakeThumbnail(bytes: 64), for: keepID)
        cache.store(fakeThumbnail(bytes: 64), for: dropID)

        cache.prune(keeping: [keepID])
        #expect(cache.url(for: keepID) != nil)
        #expect(cache.url(for: dropID) == nil)
    }

    @Test func removeDeletesSingleThumbnail() {
        let (cache, cleanup) = tempCache()
        defer { cleanup() }

        let id = UUID()
        cache.store(fakeThumbnail(bytes: 64), for: id)
        #expect(cache.url(for: id) != nil)

        cache.remove(id)
        #expect(cache.url(for: id) == nil)
    }

    @Test func strayNonThumbnailFilesAreIgnoredAndNeverEvicted() {
        // The cache only counts files named by a real capture UUID, so a foreign file
        // in the directory (a non-PNG, or a PNG whose name is not a UUID) must never
        // be counted toward the caps, evicted, or pruned (CS-029). Otherwise an
        // unrelated file could be silently deleted, or could shadow a real thumbnail.
        let (cache, cleanup) = tempCache(maxEntries: 1)
        defer { cleanup() }

        // Seed two strays directly in the cache directory: a non-PNG and a PNG whose
        // basename is not a UUID.
        try? FileManager.default.createDirectory(
            at: cache.directory, withIntermediateDirectories: true)
        let nonPNG = cache.directory.appendingPathComponent("notes.txt")
        let nonUUIDPNG = cache.directory.appendingPathComponent("logo.png")
        try? Data("hello".utf8).write(to: nonPNG)
        try? fakeThumbnail(bytes: 64).write(to: nonUUIDPNG)

        // A real thumbnail at the count cap (maxEntries == 1) would normally evict any
        // older entry — but the strays are not entries, so the write must not touch
        // them and the count reflects only the one real thumbnail.
        let realID = UUID()
        cache.store(fakeThumbnail(bytes: 64), for: realID)

        #expect(cache.count == 1)
        #expect(cache.url(for: realID) != nil)
        #expect(FileManager.default.fileExists(atPath: nonPNG.path))
        #expect(FileManager.default.fileExists(atPath: nonUUIDPNG.path))

        // Pruning to the empty keep-set drops the real thumbnail but still leaves the
        // foreign files untouched.
        cache.prune(keeping: [])
        #expect(cache.count == 0)
        #expect(cache.url(for: realID) == nil)
        #expect(FileManager.default.fileExists(atPath: nonPNG.path))
        #expect(FileManager.default.fileExists(atPath: nonUUIDPNG.path))
    }

    @Test func storedThumbnailDecodesAsImage() {
        // A real PNG round-trips through the cache as a decodable NSImage.
        let (cache, cleanup) = tempCache()
        defer { cleanup() }

        let swatch = NSImage(size: NSSize(width: 8, height: 8))
        swatch.lockFocus()
        NSColor.systemIndigo.drawSwatch(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        swatch.unlockFocus()
        guard let tiff = swatch.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            Issue.record("Failed to build a PNG fixture")
            return
        }

        let id = UUID()
        cache.store(png, for: id)
        #expect(cache.image(for: id) != nil)
    }

    // MARK: - Thumbnail generation smoke (CS-029)

    @Test func rendererProducesDecodablePNG() {
        // The default renderer runs the app's own export pipeline; a non-trivial
        // capture should yield decodable PNG bytes. (A render miss is tolerated by
        // the store, but the happy path must produce a real image.)
        let data = RecentsThumbnail.pngData(
            for: Capture(
                code: "func greet() { print(\"hi\") }", languageID: "swift", themeID: "one-dark"))
        let image = data.flatMap(NSImage.init(data:))
        #expect(image != nil)
        if let image {
            #expect(image.size.width > 0)
            #expect(image.size.height > 0)
        }
    }

    @Test func missingRenderLeavesEntryWithoutPreview() {
        // A failed thumbnail render must not drop the capture: the entry survives in
        // the list, it simply has no cached preview.
        let (cache, cleanup) = tempCache()
        defer { cleanup() }
        let store = RecentsStore(
            defaults: freshDefaults(), thumbnails: cache, renderThumbnail: { _ in nil })

        let only = capture("no preview")
        store.add(only)
        #expect(store.captures.first?.code == "no preview")
        #expect(store.thumbnail(for: only) == nil)
        #expect(cache.count == 0)
    }
}
