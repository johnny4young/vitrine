import Foundation

/// Baseline provenance shared by export and social-card fixtures. Strict runs
/// require the exact OS, architecture, Xcode and SDK builds that produced the
/// reviewed pixels; normal unit runs remain explicit render smoke.
struct GoldenManifest: Codable, Equatable {
    /// Schema version, so a future format change is detectable rather than silently
    /// mis-parsed.
    var schema: Int
    /// The runner image the committed PNGs were recorded on. The strict pixel
    /// comparison requires the live runner to equal this.
    var pinnedImage: RunnerImage
    /// Per-scenario metadata: the expected pixel dimensions and a content hash of
    /// the deterministic config, keyed by the scenario's raw name.
    var scenarios: [String: ScenarioRecord]

    /// The current schema version. Bumped only on a deliberate, reviewed format
    /// change.
    static let currentSchema = 2

    /// The on-disk file name for the manifest within the golden fixtures directory.
    static let fileName = "manifest.json"

    /// The identity of a macOS/Xcode runner image, captured from values that are
    /// stable on a given image and differ across OS/toolchain versions.
    struct RunnerImage: Codable, Equatable {
        /// macOS marketing-style version, e.g. `"15.5.0"` (major.minor.patch).
        var osVersion: String
        /// CPU architecture string from `uname` (e.g. `"arm64"`, `"x86_64"`).
        var architecture: String
        /// Swift language-feature floor. The exact compiler is pinned separately
        /// by xcodeBuild, rather than inferred from this language-mode label.
        var swiftVersion: String
        var osBuild: String
        var xcodeBuild: String
        var sdkBuild: String

        /// The live runner image, resolved at runtime. `osVersion` and
        /// `architecture` come from `ProcessInfo`/`uname`; `swiftVersion` is the
        /// compile-time Swift language version baked in by `swiftVersionString`.
        static func current() -> RunnerImage {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return RunnerImage(
                osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                architecture: machineArchitecture(),
                swiftVersion: swiftVersionString,
                osBuild: operatingSystemBuild(),
                xcodeBuild: Bundle.main.infoDictionary?["DTXcodeBuild"] as? String ?? "unknown",
                sdkBuild: Bundle.main.infoDictionary?["DTSDKBuild"] as? String ?? "unknown")
        }

        /// Read the build, not just the marketing version: rasterization can change
        /// across patch builds. Xcode/SDK identities above come from built metadata.
        private static func operatingSystemBuild() -> String {
            var size = 0
            guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
                return "unknown"
            }
            var bytes = [UInt8](repeating: 0, count: size)
            guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else {
                return "unknown"
            }
            return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }

        var isQualified: Bool {
            [osVersion, architecture, swiftVersion, osBuild, xcodeBuild, sdkBuild]
                .allSatisfy { !$0.isEmpty && $0 != "unknown" }
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
