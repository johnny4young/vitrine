import Foundation

/// Filesystem cleanup for historical editor-session stores. Current sessions stay in memory.
/// Kept at the app boundary; the Domain schema only migrates injected preferences.
enum EditorSessionMigration {
    /// The suite-name prefix used by editor sessions in earlier releases. Current sessions
    /// never create a persistent suite; this remains only as the launch sweep's match
    /// criterion so an upgrade can collect historical files safely.
    nonisolated static let legacyEditorSessionSuitePrefix =
        "com.johnny4young.vitrine.editor-session."

    /// Deletes stale per-window suite files left behind by earlier releases.
    ///
    /// Earlier per-window UUID suites could outlive a primary session, a force-quit, or
    /// a crash, and `removePersistentDomain` could leave an empty cfprefsd-owned husk.
    /// Left alone they accumulated without bound and could hold user-typed annotation
    /// text. Current sessions use ``InMemoryUserDefaults`` and cannot create these files;
    /// this migration sweep remains so upgrading users converge to the new invariant.
    ///
    /// At launch no session of *this* process exists yet, so every matching file is
    /// garbage — except one belonging to a concurrently running second instance (a dev
    /// build and an installed build share the container). The age threshold makes the
    /// sweep safe against that race: a live session's plist was written recently, a
    /// stranded one has not been touched since its run died.
    nonisolated static func sweepStaleEditorSessionSuites(
        preferencesDirectory: URL,
        olderThan age: TimeInterval = 86_400,
        now: Date = Date()
    ) {
        let fileManager = FileManager.default
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: preferencesDirectory, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
        else { return }
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix(legacyEditorSessionSuitePrefix), name.hasSuffix(".plist") else {
                continue
            }
            // Fail conservatively: a file whose modification date cannot be read is
            // *skipped*, not treated as ancient — a transient filesystem error must
            // never clear a suite that might belong to a live session. A genuinely
            // stranded file will stat fine on a later launch and be collected then.
            guard
                let modified =
                    (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate,
                now.timeIntervalSince(modified) > age
            else { continue }
            // Empty the domain first so cfprefsd's cache agrees with the deletion, then
            // remove the file itself — the half `removePersistentDomain` cannot do.
            let suiteName = String(name.dropLast(".plist".count))
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            try? fileManager.removeItem(at: file)
        }
    }

    /// Runs ``sweepStaleEditorSessionSuites(preferencesDirectory:olderThan:now:)`` off the
    /// main actor, so launch never waits on it.
    ///
    /// Each stale suite costs a `cfprefsd` round trip plus a file removal: 50 of them took
    /// about 15 ms, and even with none to remove the sweep still lists the whole directory.
    /// Nothing at launch depends on the result, and the sweep is idempotent, so a quit
    /// before it finishes only leaves the rest for the next launch.
    @concurrent
    nonisolated static func sweepStaleEditorSessionSuitesInBackground(
        preferencesDirectory: URL
    ) async {
        sweepStaleEditorSessionSuites(preferencesDirectory: preferencesDirectory)
    }

    /// The container's Preferences directory, where `cfprefsd` materializes suites.
    nonisolated static var preferencesDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences", isDirectory: true)
    }
}
