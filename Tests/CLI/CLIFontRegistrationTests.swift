import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Vitrine

/// runtime registration of the app's bundled fonts for the command-line
/// renderer.
///
/// `CLIFontRegistration` is what keeps a default CLI render pixel-identical to the
/// app: a command-line tool has no app bundle, so the bundled monospaced families
/// are not auto-registered and `NSFont(name:…)` would silently fall back to the
/// system font. These tests pin the contract that drives that guarantee — a missing
/// directory is a harmless no-op, only font files are registered, and re-running in
/// one process is idempotent (an already-registered font counts as success).
///
/// `@MainActor` so these tests are serialized with the render suites.
/// `CLIFontRegistration` itself has no actor isolation, but registering or
/// unregistering fonts mutates a process-wide Core Text table; letting that run on a
/// background thread *concurrently* with a render on the main actor (the golden-image
/// and CLI byte-identity suites) transiently invalidates Core Text's font caches
/// mid-render and shifts glyph rasterization by a few hundred PNG bytes. Pinning the
/// suite to the main actor keeps every font-table mutation ordered with respect to
/// every render, so the suites are independent of the order Swift Testing schedules
/// them in.
@MainActor
@Suite("CLI font registration")
struct CLIFontRegistrationTests {
    /// A unique scratch directory for one test.
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitrine-cli-fonts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The bundled font file name these registration tests copy and register.
    ///
    /// Deliberately **not** the render's default family (JetBrains Mono): these tests
    /// register a copy of a bundled `.ttf` from a scratch directory and then delete
    /// that directory, which perturbs the process-wide Core Text registration for that
    /// font's *contents*. If that font were JetBrains Mono — the family the golden-image
    /// and CLI byte-identity suites render in — the perturbation would subtly shift
    /// glyph rasterization (an off-by-a-few-hundred-bytes PNG difference) depending on
    /// the order Swift Testing happens to run the suites in. Using a bundled family the
    /// default render never touches keeps the Core Text registration path genuinely
    /// exercised while leaving the render's font untouched.
    private static let fontFileName = "SpaceMono-Regular.ttf"
    private static let fontResourceName = "SpaceMono-Regular"

    /// A real bundled `.ttf` from the app bundle the test host runs in. Using an
    /// actual font (not a fabricated file) means the Core Text registration path is
    /// genuinely exercised rather than always failing to parse.
    private func bundledFontURL() throws -> URL {
        try #require(
            Bundle.main.url(
                forResource: Self.fontResourceName, withExtension: "ttf",
                subdirectory: "Fonts"),
            "the test host app bundle should ship the bundled fonts")
    }

    /// Unregisters a font this suite registered from a temporary URL and drains the
    /// Core Text change notification, restoring the process's font state before the
    /// next test runs.
    ///
    /// `registerBundledFonts(in:)` registers fonts process-wide via
    /// `CTFontManagerRegisterFontsForURL(_:.process,_:)`. Two things make that unsafe to
    /// leave behind: a registration pointing at a file this test is about to delete is
    /// *dangling*, and — more subtly — each register/unregister posts an **asynchronous**
    /// fonts-changed notification that invalidates Core Text's glyph caches when the run
    /// loop next services it. If that notification is still in flight when the very next
    /// render runs (e.g. the CLI byte-identity or golden-image suites), it invalidates
    /// caches *mid-comparison* and shifts rasterization by a few hundred PNG bytes.
    /// Unregistering and then briefly spinning the run loop forces that invalidation to
    /// complete here, while no render is in progress, so these registration tests cannot
    /// perturb a later render regardless of the order Swift Testing runs them in.
    private func unregisterFont(at url: URL) {
        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        // Let the pending fonts-changed notification be delivered now, not during a
        // subsequent render.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    @Test func nilDirectoryRegistersNothing() {
        // No bundled `Fonts` folder (a system-font-only setup) must not crash and
        // registers nothing, so a render still works without the bundled fonts.
        #expect(CLIFontRegistration.registerBundledFonts(in: nil).isEmpty)
    }

    @Test func onlyFontFilesAreRegistered() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A directory with no font files (here a stray license note) registers
        // nothing: non-`.ttf`/`.otf` entries are filtered out, not handed to Core
        // Text.
        try "not a font".write(
            to: directory.appendingPathComponent("LICENSES.md"), atomically: true,
            encoding: .utf8)
        #expect(CLIFontRegistration.registerBundledFonts(in: directory).isEmpty)
    }

    @Test func registersABundledFontAndSkipsNonFonts() throws {
        let directory = try makeTempDirectory()
        // Copy a genuine `.ttf` alongside a non-font file. Only the font is reported.
        let font = try bundledFontURL()
        let registeredFontURL = directory.appendingPathComponent(Self.fontFileName)
        try FileManager.default.copyItem(at: font, to: registeredFontURL)
        // Unregister before deleting the file so no dangling process-wide registration
        // survives to corrupt later renders (see `unregisterFont(at:)`).
        defer {
            unregisterFont(at: registeredFontURL)
            try? FileManager.default.removeItem(at: directory)
        }
        try "ignore me".write(
            to: directory.appendingPathComponent("README.txt"), atomically: true,
            encoding: .utf8)

        let registered = CLIFontRegistration.registerBundledFonts(in: directory)
        #expect(registered == [Self.fontFileName])
    }

    @Test func reRegisteringTheSameFontIsIdempotent() throws {
        let directory = try makeTempDirectory()
        let font = try bundledFontURL()
        let registeredFontURL = directory.appendingPathComponent(Self.fontFileName)
        try FileManager.default.copyItem(at: font, to: registeredFontURL)
        // Unregister before deleting the file so no dangling process-wide registration
        // survives to corrupt later renders (see `unregisterFont(at:)`).
        defer {
            unregisterFont(at: registeredFontURL)
            try? FileManager.default.removeItem(at: directory)
        }

        // A second pass in the same process hits Core Text's "already registered"
        // result, which the code treats as success — so the font is still reported
        // and the call never fails (the in-process re-run no-op the docs promise).
        _ = CLIFontRegistration.registerBundledFonts(in: directory)
        let again = CLIFontRegistration.registerBundledFonts(in: directory)
        #expect(again == [Self.fontFileName])
    }
}
