import Foundation

/// Locates the committed golden-fixtures directory in the source tree.
///
/// The unit-test bundle runs from a built product, not the repository, so the
/// fixtures cannot be found relative to the working directory. Instead the path is
/// anchored to this source file via `#filePath`: the recorder writes PNGs here and
/// the comparison suite reads them from the same place, so a freshly recorded
/// baseline is exactly what the next run compares against.
enum GoldenPaths {
    /// The absolute path to the directory holding the committed fixtures
    /// (`<repo>/Tests/Fixtures/Golden/`), derived from this file's location
    /// (`<repo>/Tests/GoldenPaths.swift`). This is where the comparison suite
    /// *reads* fixtures from.
    static var fixturesDirectory: URL {
        // #filePath → <repo>/Tests/GoldenPaths.swift; drop the file name to reach
        // <repo>/Tests, then descend into Fixtures/Golden.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("Golden", isDirectory: true)
    }

    /// Where the recorder *writes* fixtures.
    ///
    /// The unit-test host runs inside the sandboxed app, which cannot write into
    /// the source tree (or even `/tmp`) — only into its own container temp. So the
    /// recorder stages PNGs and the manifest in a fixed subdirectory of
    /// `NSTemporaryDirectory()`, prints that absolute path (`GOLDEN OUTPUT …`), and
    /// `make record-goldens` copies the staged files into `Tests/Fixtures/Golden/`
    /// from outside the sandbox. An explicit `VITRINE_GOLDEN_OUTPUT_DIR` override is
    /// honored for any (non-sandboxed) context that can target a path directly.
    static var recordingOutputDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["VITRINE_GOLDEN_OUTPUT_DIR"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vitrine-golden-record", isDirectory: true)
    }

    /// The on-disk URL of a scenario's golden PNG within the fixtures directory.
    static func goldenURL(for scenario: GoldenScenario) -> URL {
        fixturesDirectory.appendingPathComponent(scenario.fileName)
    }
}
