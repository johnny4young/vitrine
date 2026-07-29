import CoreGraphics

@testable import Vitrine

/// Fixtures shared by the export suites, so a config or a card size is described once
/// rather than redefined per file. Mirrors `CLITestSupport` for the CLI suites.
enum ExportTestFixtures {
    /// A minimal renderable config. `mutate` adjusts the one property a test is about,
    /// which keeps each test's setup to the thing it actually varies.
    static func sampleConfig(
        _ mutate: (inout SnapshotConfig) -> Void = { _ in }
    ) -> SnapshotConfig {
        var config = SnapshotConfig()
        config.code = "let answer = 42"
        mutate(&config)
        return config
    }

    /// The simple-template card size (the 1200×630 social aspect the vector template
    /// serializes against).
    static let cardSize = CGSize(width: 1200, height: 630)
}
