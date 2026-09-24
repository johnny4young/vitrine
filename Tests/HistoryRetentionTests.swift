import AppKit
import Foundation
import Testing
import VitrineDomain
import VitrineRendering

@testable import Vitrine

@MainActor
@Suite("History retention")
struct HistoryRetentionTests {
    private func cache() -> RecentsThumbnailCache {
        RecentsThumbnailCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString))
    }

    private var secret: String { "gh" + "p_" + String(repeating: "x", count: 36) }

    @Test func explicitRedactionsNeverReachRecordsThumbnailsSearchOrReopening() throws {
        let defaults = testDefaults()
        let cache = cache()
        defer { cache.clear() }
        var rendered: [String] = []
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache,
            renderThumbnail: {
                rendered.append($0.code)
                return Data($0.code.utf8)
            })
        var config = SnapshotConfig(code: "\(secret)\nvisible", language: .swift)
        config.redactedLineRanges = [1...1]
        #expect(store.record(config) == .saved)
        let capture = try #require(store.captures.first)
        #expect(capture.code == "[redacted]\nvisible")
        #expect(rendered == [capture.code])
        #expect(!capture.matchesSearch(secret))
        #expect(!capture.applying(to: SnapshotConfig()).code.contains(secret))
        let data = try #require(defaults.data(forKey: "recentCaptures"))
        #expect(!String(decoding: data, as: UTF8.self).contains(secret))
        let reloaded = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { _ in nil })
        #expect(reloaded.captures == [capture])
    }

    @Test(arguments: [CaptureRetentionPolicy.Consent.doNotSave, .saveSanitized, .keepOriginal])
    func suspiciousCaptureRequiresANewDecisionBeforeAnyDiskWrite(
        _ choice: CaptureRetentionPolicy.Consent
    ) throws {
        let defaults = testDefaults()
        let cache = cache()
        defer { cache.clear() }
        var rendered: [String] = []
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache,
            renderThumbnail: {
                rendered.append($0.code)
                return Data($0.code.utf8)
            })
        let config = SnapshotConfig(code: secret, language: .swift)
        #expect(store.record(config) == .requiresConsent)
        #expect(store.captures.isEmpty)
        #expect(defaults.data(forKey: "recentCaptures") == nil)
        #expect(rendered.isEmpty)
        let result = store.record(config) { _ in
            #expect(defaults.data(forKey: "recentCaptures") == nil)
            #expect(rendered.isEmpty)
            return choice
        }
        if choice == .doNotSave {
            #expect(result == .omitted)
            #expect(defaults.data(forKey: "recentCaptures") == nil)
            #expect(rendered.isEmpty)
        } else {
            #expect(result == .saved)
            #expect(store.captures.first?.code == (choice == .keepOriginal ? secret : "[redacted]"))
            #expect(rendered.count == 1)
        }
        let before = defaults.data(forKey: "recentCaptures")
        #expect(store.record(config) == .requiresConsent)
        #expect(defaults.data(forKey: "recentCaptures") == before)
        #expect(config.code == secret, "history policy cannot rewrite the requested export")
    }

    @Test func originalConsentCannotRestoreExplicitlyRedactedRows() {
        var config = SnapshotConfig(code: "private original\n\(secret)", language: .swift)
        config.redactedLineRanges = [1...1]
        #expect(
            CaptureRetentionPolicy.decide(config)
                == .requiresConsent(
                    original: "[redacted]\n\(secret)", sanitized: "[redacted]\n[redacted]"))
    }

    @Test func terminalSanitizationUsesFinalRowsAndDropsHiddenTranscriptSecrets() {
        var config = SnapshotConfig(code: "\(secret)\u{1B}[2J\u{1B}[Hvisible", language: .terminal)
        #expect(
            CaptureRetentionPolicy.decide(config)
                == .requiresConsent(original: config.code, sanitized: "visible"))
        config.code = "public\r\(secret)\nnext"
        config.redactedLineRanges = [1...1]
        guard case .safe(let safe) = CaptureRetentionPolicy.decide(config) else {
            Issue.record(
                "explicit terminal redaction should remove the detected secret before retention")
            return
        }
        #expect(!safe.contains(secret))
        #expect(!safe.contains("\u{1B}"))
        #expect(safe.contains("[redacted]"))
    }

    @Test func imagesNeverRetainTheCodeHiddenBehindThemAndBlurIsNotRedaction() {
        var config = SnapshotConfig(code: "ordinary code", language: .swift)
        config.foregroundImage = ImageReference(fileName: "image.png")
        #expect(CaptureRetentionPolicy.decide(config) == .omit)
        config.foregroundImage = nil
        config.annotations = [Annotation(kind: .blur, start: .zero, end: CGPoint(x: 1, y: 1))]
        #expect(CaptureRetentionPolicy.decide(config) == .safe("ordinary code"))
    }

    @Test func disabledHistoryPreservesOldDataAndInvalidatesAnOpenConsent() throws {
        let defaults = testDefaults()
        let cache = cache()
        defer { cache.clear() }
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { Data($0.code.utf8) })
        #expect(store.record(SnapshotConfig(code: "first", language: .swift)) == .saved)
        let before = defaults.data(forKey: "recentCaptures")
        #expect(
            store.record(SnapshotConfig(code: secret, language: .swift)) { _ in
                store.isEnabled = false
                return .keepOriginal
            } == .omitted)
        #expect(defaults.data(forKey: "recentCaptures") == before)
        #expect(store.record(SnapshotConfig(code: "second", language: .swift)) == .omitted)
        let reloaded = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { _ in nil })
        #expect(!reloaded.isEnabled)
        #expect(reloaded.captures.map(\.code) == ["first"])
        reloaded.clear()
        #expect(reloaded.captures.isEmpty)
        #expect(!reloaded.isEnabled)
    }

    @Test func malformedRetentionPreferenceDoesNotEnableWrites() {
        let defaults = testDefaults()
        defaults.set("invalid", forKey: "captureHistoryEnabled")
        let cache = cache()
        defer { cache.clear() }
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { _ in nil })
        #expect(!store.isEnabled)
        #expect(store.record(SnapshotConfig(code: "new", language: .swift)) == .omitted)
        #expect(defaults.object(forKey: "recentCaptures") == nil)
    }

    @Test func cancellationAndUnknownModalResultsNeverGrantConsent() {
        for response in [
            NSApplication.ModalResponse.cancel, .abort, .alertFirstButtonReturn,
            .init(rawValue: -999),
        ] {
            #expect(HistoryConsentPrompt.choice(for: response) == .doNotSave)
        }
        #expect(HistoryConsentPrompt.choice(for: .alertSecondButtonReturn) == .saveSanitized)
        #expect(HistoryConsentPrompt.choice(for: .alertThirdButtonReturn) == .keepOriginal)
    }
}

@MainActor
@Suite("History archive recovery")
struct HistoryArchiveRecoveryTests {
    @Test(arguments: [false, true])
    func partialDamagePreservesRawArchiveAndCacheUntilExplicitRecovery(_ truncated: Bool) throws {
        let capture = Capture(
            code: "brace } quote \\\" and unicode 日本語", languageID: "swift", themeID: "one-dark",
            isPinned: true)
        let encoded = try JSONEncoder().encode(capture)
        var data = Data("[".utf8)
        data.append(encoded)
        data.append(Data((truncated ? ", {\"code\":\"unfinished" : ", {\"invalid\":true}]").utf8))
        let defaults = testDefaults()
        defaults.set(data, forKey: "recentCaptures")
        let cache = RecentsThumbnailCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString))
        defer { cache.clear() }
        let orphan = UUID()
        cache.store(Data([1, 2, 3]), for: orphan)
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { _ in nil })
        #expect(store.needsRecovery)
        #expect(store.hasLegacyHistory)
        #expect(store.captures == [capture])
        #expect(defaults.data(forKey: "recentCaptures") == data)
        #expect((cache.url(for: orphan) != nil))
        #expect(store.record(SnapshotConfig(code: "new", language: .swift)) == .omitted)
        #expect(!store.remove(id: capture.id))
        #expect(!store.updatePinned(id: capture.id, isPinned: false))
        #expect(store.clearUnpinned() == 0)
        #expect(defaults.data(forKey: "recentCaptures") == data)
        store.recoverAvailableCaptures()
        #expect(!store.needsRecovery)
        #expect(
            try JSONDecoder().decode(
                [Capture].self, from: #require(defaults.data(forKey: "recentCaptures"))) == [
                    capture
                ])
        #expect(!(cache.url(for: orphan) != nil))
    }

    @Test func fullyUnreadableDataIsOnlyDiscardedByExplicitPurge() {
        let defaults = testDefaults()
        let original = Data([0xFF, 0xFE, 0xFD])
        defaults.set(original, forKey: "recentCaptures")
        let cache = RecentsThumbnailCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString))
        defer { cache.clear() }
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { _ in nil })
        #expect(store.needsRecovery)
        store.recoverAvailableCaptures()
        #expect(defaults.data(forKey: "recentCaptures") == original)
        store.clear()
        #expect(!store.needsRecovery)
        #expect(!store.hasLegacyHistory)
        #expect(defaults.data(forKey: "recentCaptures") != original)
    }

    @Test func wrongStorageTypeIsPreservedUntilPurge() {
        let defaults = testDefaults()
        defaults.set("invalid archive type", forKey: "recentCaptures")
        let cache = RecentsThumbnailCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString))
        defer { cache.clear() }
        let id = UUID()
        cache.store(Data([1]), for: id)
        let store = RecentsStore(
            defaults: defaults, thumbnails: cache, renderThumbnail: { _ in nil })
        #expect(store.needsRecovery)
        #expect(cache.url(for: id) != nil)
        #expect(defaults.string(forKey: "recentCaptures") == "invalid archive type")
        #expect(store.record(SnapshotConfig(code: "new", language: .swift)) == .omitted)
        store.clear()
        #expect(cache.url(for: id) == nil)
    }

    @Test func duplicateIdentitiesAreRecoverableAndNestedObjectsAreNotPromoted() throws {
        let capture = Capture(code: "valid", languageID: "swift", themeID: "one-dark")
        let duplicate = HistoryArchiveRecovery.decode(try JSONEncoder().encode([capture, capture]))
        #expect(duplicate.needsRecovery)
        #expect(duplicate.captures == [capture])
        let object = String(decoding: try JSONEncoder().encode(capture), as: UTF8.self)
        let nested = HistoryArchiveRecovery.decode(Data("[[\(object)], {\"unfinished\":".utf8))
        #expect(nested.needsRecovery)
        #expect(nested.captures.isEmpty)
        let mismatched = HistoryArchiveRecovery.decode(Data("[[}, \(object)".utf8))
        #expect(mismatched.captures.isEmpty, "a mismatched closer cannot promote a nested record")
    }

    @Test func emptyLegacyArchiveNeedsNoPrivacyNotice() throws {
        let defaults = testDefaults()
        defaults.set(try JSONEncoder().encode([Capture]()), forKey: "recentCaptures")
        let thumbnails = RecentsThumbnailCache(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                UUID().uuidString))
        defer { thumbnails.clear() }
        let store = RecentsStore(
            defaults: defaults, thumbnails: thumbnails, renderThumbnail: { _ in nil })
        #expect(!store.needsRecovery)
        #expect(!store.hasLegacyHistory)
    }

    @Test func recoveryFixtureSeedsOnlyAnIsolatedUITestSuiteOnce() throws {
        let arguments = ["Vitrine", "--history-recovery-demo"]
        let isolated = ["VITRINE_USER_DEFAULTS_SUITE": "ui-test"]
        let standard = testDefaults()
        AppLaunchArgumentHandler.seedPreLaunchFixtures(
            in: standard, arguments: arguments, environment: [:])
        #expect(standard.object(forKey: "recentCaptures") == nil)
        let defaults = testDefaults()
        AppLaunchArgumentHandler.seedPreLaunchFixtures(
            in: defaults, arguments: ["Vitrine"], environment: isolated)
        #expect(defaults.object(forKey: "recentCaptures") == nil)
        AppLaunchArgumentHandler.seedPreLaunchFixtures(
            in: defaults, arguments: arguments, environment: isolated)
        let seeded = try #require(defaults.data(forKey: "recentCaptures"))
        #expect(HistoryArchiveRecovery.decode(seeded).needsRecovery)
        defaults.removeObject(forKey: "recentCaptures")
        AppLaunchArgumentHandler.seedPreLaunchFixtures(
            in: defaults, arguments: arguments, environment: isolated)
        #expect(
            defaults.object(forKey: "recentCaptures") == nil, "a purge is not undone on relaunch")
    }
}
