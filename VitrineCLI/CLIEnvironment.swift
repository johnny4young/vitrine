import Foundation

/// Locates resources the `vitrine` executable ships with.
///
/// The binary runs from two layouts. As a development tool, resources are copied
/// into the build output **next to the binary**. As the embedded copy inside the
/// shipped app (`Vitrine.app/Contents/MacOS/vitrine-cli`, symlinked onto PATH by
/// the Homebrew cask), the fonts live in the app's `Contents/Resources/Fonts`. The
/// `Fonts` directory is found by walking outward from the executable's own
/// location — beside the binary, in a `Resources` sibling, then in the enclosing
/// bundle's `Resources` — with PATH symlinks resolved first. The lookup is
/// read-only and contained to the executable's surroundings; it never reaches
/// into the user's file system, so it adds nothing to the sandbox surface.
enum CLIEnvironment {
    /// The directory holding the bundled monospaced fonts, or `nil` when it cannot
    /// be located (in which case the CLI falls back to system fonts).
    static var bundledFontsDirectory: URL? {
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()

        // Candidate layouts, in order of likelihood for a tool build product. The
        // last covers the executable embedded in the app bundle: from
        // `Contents/MacOS/` the fonts sit in the sibling `Contents/Resources/`.
        let candidates = [
            executableDirectory.appendingPathComponent("Fonts", isDirectory: true),
            executableDirectory.appendingPathComponent("Resources/Fonts", isDirectory: true),
            executableDirectory.deletingLastPathComponent()
                .appendingPathComponent("Resources/Fonts", isDirectory: true),
        ]
        return candidates.first { directory in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: directory.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }
}
