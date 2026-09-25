import Foundation
import Testing

/// Smoke is explicit and never claims pixel qualification. Strict cannot fall
/// back to smoke when a fixture or its environment is unavailable.
enum GoldenValidation {
    enum Failure: Error {
        case invalidMode, missingBaseline, unqualifiedEnvironment
    }

    static func shouldCompare(
        manifest: GoldenManifest?, fixtureExists: Bool,
        mode: String = ProcessInfo.processInfo.environment["VITRINE_GOLDEN_MODE"] ?? "",
        current: GoldenManifest.RunnerImage = .current()
    ) throws -> Bool {
        switch mode {
        case "", "smoke": return false
        case "strict":
            guard let manifest, fixtureExists, manifest.schema == GoldenManifest.currentSchema
            else {
                throw Failure.missingBaseline
            }
            guard current.isQualified, manifest.pinnedImage == current else {
                throw Failure.unqualifiedEnvironment
            }
            return true
        default: throw Failure.invalidMode
        }
    }

    /// Emitted only after a qualified, successful production-render comparison.
    /// The outer gate requires one receipt per expected scenario, including social.
    static func recordComparison(kind: String, scenario: String) throws {
        struct Receipt: Encodable {
            var kind: String
            var scenario: String
            var image: GoldenManifest.RunnerImage
        }
        let data = try JSONEncoder().encode(
            Receipt(kind: kind, scenario: scenario, image: .current()))
        print("GOLDEN RESULT " + String(decoding: data, as: UTF8.self))
    }
}

struct GoldenValidationTests {
    @Test func smokeDoesNotPretendToCompareMissingFixtures() throws {
        #expect(
            try !GoldenValidation.shouldCompare(manifest: nil, fixtureExists: false, mode: "smoke"))
    }

    @Test func strictRejectsMissingOrUnqualifiedBaselines() throws {
        let current = GoldenManifest.RunnerImage.current()
        var manifest = GoldenManifest(
            schema: GoldenManifest.currentSchema, pinnedImage: current, scenarios: [:])
        #expect(throws: GoldenValidation.Failure.missingBaseline) {
            try GoldenValidation.shouldCompare(manifest: nil, fixtureExists: true, mode: "strict")
        }
        #expect(throws: GoldenValidation.Failure.missingBaseline) {
            try GoldenValidation.shouldCompare(
                manifest: manifest, fixtureExists: false, mode: "strict")
        }
        #expect(current.isQualified)
        #expect(
            try GoldenValidation.shouldCompare(
                manifest: manifest, fixtureExists: true, mode: "strict"))
        manifest.pinnedImage.osBuild = "different-build"
        #expect(throws: GoldenValidation.Failure.unqualifiedEnvironment) {
            try GoldenValidation.shouldCompare(
                manifest: manifest, fixtureExists: true, mode: "strict")
        }
        manifest.pinnedImage = current
        manifest.pinnedImage.xcodeBuild = "different-compiler"
        #expect(throws: GoldenValidation.Failure.unqualifiedEnvironment) {
            try GoldenValidation.shouldCompare(
                manifest: manifest, fixtureExists: true, mode: "strict")
        }
    }

    @Test func strictRejectsAnUnidentifiedHostEvenWhenTheManifestMatches() {
        var unknown = GoldenManifest.RunnerImage.current()
        unknown.xcodeBuild = "unknown"
        let manifest = GoldenManifest(
            schema: GoldenManifest.currentSchema, pinnedImage: unknown, scenarios: [:])
        #expect(!unknown.isQualified)
        #expect(throws: GoldenValidation.Failure.unqualifiedEnvironment) {
            try GoldenValidation.shouldCompare(
                manifest: manifest, fixtureExists: true, mode: "strict", current: unknown)
        }
    }

    @Test func invalidModeFailsClosed() {
        #expect(throws: GoldenValidation.Failure.invalidMode) {
            try GoldenValidation.shouldCompare(manifest: nil, fixtureExists: false, mode: "strcit")
        }
    }
}
