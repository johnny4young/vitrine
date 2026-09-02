/// The `vitrine` usage text, shown for `--help` and on a usage error.
///
/// `nonisolated` and generated from ``CLIArgumentSchema`` so `CLIError.message` —
/// itself nonisolated — can compose it from any context without duplicating the option
/// catalog.
nonisolated enum CLIUsage {
    static let text = """
        vitrine — render code to an image from the command line.

        USAGE:
          vitrine terminal-capture <capture-file> (--copy | --edit) [--terminal-width <n>] [--filename <text> --title <text>]
          vitrine render <input-file> --out <image> [options]
          vitrine render --image <input-image> --out <image> [options]
          vitrine render --stdin --copy [options]
          vitrine render --stdin --out <image> [--stdin-name <name>] [options]
          vitrine render --git-diff <revision-range> [--git-path <path>]... --out <image> [options]
          vitrine render --git-staged [--git-path <path>]... --out <image> [options]
          vitrine render (<input-file> | --stdin | --git-diff <range> | --git-staged) --edit [options]
          vitrine multi-size (<input-file> | --stdin | --git-diff <range> | --git-staged) --out <output-folder> [--presets <ids>] [options]
          vitrine batch <input-folder> --out <output-folder> [options]
          vitrine recipe <validate|show> <path> [--json]
          vitrine list <all|themes|languages|presets|style-presets|fonts|backgrounds|background-fits|frames|frame-appearances|watermark-positions|formats|profiles> [--json]
          vitrine --version [--json]
          vitrine version [--json]
          vitrine shell-init [zsh|bash|fish]   Print the terminal-capture shell helpers.

        ACCESS:
          `vgrab` uses the constrained terminal-capture command and is free. General
          render, multi-size, batch, vpane, and other automation capabilities require PRO.

        OPTIONS:
        \(CLIArgumentSchema.helpText)

        Code rendering is fully local: it never needs the network, screen recording,
        or Accessibility permissions.
        """
}
