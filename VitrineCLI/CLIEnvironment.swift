import Foundation

/// Locates resources the `vitrine` executable ships with (CS-033).
///
/// A command-line tool has no `.app` bundle, so resources are copied into the build
/// output **next to the binary**. The bundled `Fonts` directory is found by walking
/// outward from the executable's own location: first beside the binary, then in a
/// `Resources` sibling — covering both a flat tool layout and a wrapped bundle. The
/// lookup is read-only and contained to the executable's directory; it never reaches
/// into the user's file system, so it adds nothing to the sandbox surface.
enum CLIEnvironment {
    /// The directory holding the bundled monospaced fonts, or `nil` when it cannot
    /// be located (in which case the CLI falls back to system fonts).
    static var bundledFontsDirectory: URL? {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        // Candidate layouts, in order of likelihood for a tool build product.
        let candidates = [
            executableDirectory.appendingPathComponent("Fonts", isDirectory: true),
            executableDirectory.appendingPathComponent("Resources/Fonts", isDirectory: true),
        ]
        return candidates.first { directory in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: directory.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }
}
