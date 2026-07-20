import Foundation

/// The manifest recorded next to the golden PNGs (`Tests/Fixtures/Golden/manifest.json`),
/// pinning the runner image the committed fixtures were generated on.
///
/// Text rasterization differs across macOS/Xcode versions, so a golden PNG is only
/// a valid baseline on the image that produced it. This manifest records *which*
/// image that is, so the comparison suite (`GoldenImageTests`) can run a strict
/// pixel diff only when the current runner matches — and otherwise log `GOLDEN
/// SKIP` while still exercising the render end to end. The recorder
/// (`GoldenRecorderTests`) writes this file alongside the PNGs, so the pin and the
/// fixtures always travel together.
struct GoldenManifest: Codable, Equatable {
    /// Schema version, so a future format change is detectable rather than silently
    /// mis-parsed.
    var schema: Int
    /// The runner image the committed PNGs were recorded on. The strict pixel
    /// comparison runs only when the live runner equals this.
    var pinnedImage: RunnerImage
    /// Per-scenario metadata: the expected pixel dimensions and a content hash of
    /// the deterministic config, keyed by the scenario's raw name.
    var scenarios: [String: ScenarioRecord]

    /// The current schema version. Bumped only on a deliberate, reviewed format
    /// change.
    static let currentSchema = 1

    /// The on-disk file name for the manifest within the golden fixtures directory.
    static let fileName = "manifest.json"

    /// The identity of a macOS/Xcode runner image, captured from values that are
    /// stable on a given image and differ across OS/toolchain versions.
    struct RunnerImage: Codable, Equatable {
        /// macOS marketing-style version, e.g. `"15.5.0"` (major.minor.patch).
        var osVersion: String
        /// CPU architecture string from `uname` (e.g. `"arm64"`, `"x86_64"`).
        var architecture: String
        /// The Swift compiler/language version the fixtures were built with, e.g.
        /// `"6.0"`. Recorded because a compiler change can shift text metrics.
        var swiftVersion: String

        /// The live runner image, resolved at runtime. `osVersion` and
        /// `architecture` come from `ProcessInfo`/`uname`; `swiftVersion` is the
        /// compile-time Swift language version baked in by `swiftVersionString`.
        static func current() -> RunnerImage {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return RunnerImage(
                osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                architecture: machineArchitecture(),
                swiftVersion: swiftVersionString)
        }

        /// The hardware architecture string (`arm64`, `x86_64`, …) via `uname`.
        /// A CPU model, not a device identifier.
        private static func machineArchitecture() -> String {
            var info = utsname()
            guard uname(&info) == 0 else { return "unknown" }
            return withUnsafeBytes(of: &info.machine) { raw in
                let bytes = raw.prefix { $0 != 0 }
                return String(decoding: bytes, as: UTF8.self)
            }
        }

        /// The Swift language version the test bundle was compiled with, derived
        /// from the compiler's `#if swift(...)` ladder. Recorded in the pin so a
        /// toolchain bump that could move text metrics is visible in the manifest.
        static var swiftVersionString: String {
            #if swift(>=6.2)
                return "6.2"
            #elseif swift(>=6.1)
                return "6.1"
            #elseif swift(>=6.0)
                return "6.0"
            #elseif swift(>=5.10)
                return "5.10"
            #else
                return "unknown"
            #endif
        }
    }

    /// What the manifest records for one scenario.
    struct ScenarioRecord: Codable, Equatable {
        /// Expected rendered width in pixels.
        var width: Int
        /// Expected rendered height in pixels.
        var height: Int
        /// A stable hash of the scenario's deterministic config (see
        /// `GoldenScenario.configFingerprint`), so a change to the *input* that
        /// would invalidate a fixture is detectable even before pixels are compared.
        var configFingerprint: String
    }

    /// The default URL of the manifest under a golden fixtures directory.
    static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Loads and decodes a manifest from `directory`, or `nil` if it is absent or
    /// unparseable (an absent manifest means "no pin recorded yet").
    static func load(from directory: URL) -> GoldenManifest? {
        guard let data = try? Data(contentsOf: url(in: directory)) else { return nil }
        return try? JSONDecoder().decode(GoldenManifest.self, from: data)
    }

    /// Encodes the manifest as pretty-printed, key-sorted JSON, the stable form
    /// written next to the fixtures (deterministic so a re-record produces a
    /// minimal diff).
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
