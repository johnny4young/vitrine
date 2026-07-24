/// The `vitrine` usage text, shown for `--help` and on a usage error.
///
/// `nonisolated` (a pure static string) so `CLIError.message` — itself nonisolated —
/// can compose it, and so the executable and tests can read it from any context.
nonisolated enum CLIUsage {
    static let text = """
        vitrine — render code to an image from the command line.

        USAGE:
          vitrine render <input-file> --out <image> [options]
          vitrine render --image <input-image> --out <image> [options]
          vitrine render --stdin --copy [options]
          vitrine render --stdin --out <image> [--stdin-name <name>] [options]
          vitrine render --git-diff <revision-range> [--git-path <path>]... --out <image> [options]
          vitrine render --git-staged [--git-path <path>]... --out <image> [options]
          vitrine render (<input-file> | --stdin | --git-diff <range> | --git-staged) --edit [options]
          vitrine multi-size (<input-file> | --stdin | --git-diff <range> | --git-staged) --out <output-folder> [--presets <ids>] [options]
          vitrine batch <input-folder> --out <output-folder> [options]
          vitrine list <all|themes|languages|presets|style-presets|fonts|backgrounds|background-fits|frames|frame-appearances|watermark-positions|formats|profiles> [--json]
          vitrine --version [--json]
          vitrine version [--json]
          vitrine shell-init [zsh|bash|fish]   Print the terminal-capture shell helpers.

        OPTIONS:
          -o, --out <path>       Output image path, or folder for multi-size/batch.
          -q, --quiet            Suppress success output; errors still print.
          --json                 Print render/multi-size/batch success output as JSON
                                 (not with --quiet).
          --copy                 Copy the rendered image to the clipboard.
          -e, --edit             Open the source in Vitrine's editor instead of
                                 rendering (no image is written; not with --copy/--out).
          --stdin                Read the source from standard input (e.g. a pipe).
          --git-diff <range>     Render a local Git revision/range (e.g. HEAD or
                                 main...HEAD) without invoking a shell.
          --git-staged           Render only changes staged in the local Git index.
          --git-path <path>      Limit a Git diff source to a path. Repeat for multiple paths.
          --git-context <0...100>
                                 Unchanged lines around each Git hunk (defaults to 3).
          --image <path>         Beautify a local image instead of rendering code.
          --frame <id>           Frame for --image: none, macos-window, browser,
                                 macbook, or iphone. Use `vitrine list frames`.
          --frame-appearance <id>
                                 Framed-image chrome: auto, light, or dark.
          --stdin-name <name>    With --stdin, infer language and default metadata
                                 from this filename; no file is read.
          --theme <id>           Syntax theme id (e.g. one-dark, dracula, nord).
          --language <id>        Language id (e.g. swift, python, terminal). Inferred
                                 when omitted.
          --preset <id>          Destination preset. Use `vitrine list presets`.
          --presets <ids>        Multi-size only: comma-separated destination ids,
                                 or all (the default). Use `vitrine list presets`.
          --style-preset <id>    Built-in presentation preset. Use
                                 `vitrine list style-presets`.
          --canvas-size <WxH>    Exact logical canvas size (64-2048 per axis).
                                 Final pixels are multiplied by --scale.
          --scale <1|2|3>        Export resolution multiplier. Defaults to the app
                                 default, or the preset's recommended scale.
          --font <family>        Code font family. Use `vitrine list fonts`.
          --font-ligatures       Enable programming ligatures when the font supports them.
          --no-font-ligatures    Disable programming ligatures.
          --font-size <n>        Code font size in points (10-20).
          --padding <n>          Canvas padding in points (16-64).
          --corner-radius <n>    Code-card corner radius in points (0-48).
          --shadow-radius <n>    Drop-shadow blur radius in points (0-40).
          --terminal-width <n>   Reconstruct terminal output at exactly n columns
                                 instead of inferring the width (1-1000). Only
                                 affects --language terminal; set by `vgrab -w`.
          --wrap-columns <n>     Soft-wrap long code lines at n columns (40-200).
          --format-code          Tidy indentation locally before rendering
                                 (--tidy is also accepted).
          --format <png|pdf|heic|avif>
                                 Output format. Defaults to png; pdf is the vector
                                 option; heic and avif are compact raster options.
          --profile <srgb|p3>    PNG color profile. Defaults to srgb.
          --transparent          Render a real transparent background.
          --background <id>      Built-in gradient. Use `vitrine list backgrounds`.
          --background-color <hex>
                                 Solid RGB/RGBA hex color (for example '#1E293B').
          --background-gradient <hex,hex,...>
                                 Custom gradient with two or more RGB/RGBA colors.
          --background-angle <degrees>
                                 Custom gradient angle from 0 through 360; requires
                                 --background-gradient (defaults to 135).
          --background-image <path>
                                 Local image used as the canvas background.
          --background-fit <fill|fit>
                                 Sizing for --background-image (defaults to fill).
          --background-blur <0...40>
                                 Blur radius for --background-image in points.
          --background-dimming <0...1>
                                 Dark overlay strength for --background-image.
          --watermark <text>     Add text to the rendered watermark badge.
          --watermark-logo <path>
                                 Add a local image to the watermark badge.
          --watermark-color <hex>
                                 Watermark text tint; requires --watermark.
          --watermark-position <corner|free>
                                 Watermark placement: bottom-right, bottom-left,
                                 top-right, top-left, or free; requires watermark
                                 text or a logo.
          --watermark-x <0...1>  Normalized horizontal center for free placement.
          --watermark-y <0...1>  Normalized vertical center for free placement; x/y
                                 must be provided together with position free.
          --callout <text>       Add a text callout through the annotation layer.
          --callout-x <0...1>    Normalized horizontal anchor (defaults to 0.5).
          --callout-y <0...1>    Normalized vertical anchor (defaults to 0.5); x/y
                                 must be provided together.
          --callout-color <hex>  Callout RGB/RGBA text color; requires --callout.
          --callout-size <2...28>
                                 Callout size weight; requires --callout.
          --counter <1...99>     Add a numbered annotation badge.
          --counter-x <0...1>    Normalized horizontal center (defaults to 0.5).
          --counter-y <0...1>    Normalized vertical center (defaults to 0.5); x/y
                                 must be provided together.
          --counter-color <hex>  Counter RGB/RGBA fill color; requires --counter.
          --counter-size <2...28>
                                 Counter size weight; requires --counter.
          --arrow <x1,y1,x2,y2> Add a repeatable arrow from normalized tail to head.
          --arrow-color <hex>   RGB/RGBA stroke color for every arrow; requires --arrow.
          --arrow-size <2...28> Stroke weight for every arrow; requires --arrow.
          --line <x1,y1,x2,y2>  Add a repeatable line between normalized coordinates.
          --line-color <hex>    RGB/RGBA stroke color for every line; requires --line.
          --line-size <2...28>  Stroke weight for every line; requires --line.
          --rectangle <x1,y1,x2,y2>
                                 Outline a repeatable normalized box.
          --rectangle-color <hex>
                                 Stroke color for every rectangle; requires --rectangle.
          --rectangle-size <2...28>
                                 Stroke weight for every rectangle; requires --rectangle.
          --highlighter <x1,y1,x2,y2>
                                 Highlight a repeatable normalized region.
          --highlighter-color <hex>
                                 Fill color for every highlighter; requires --highlighter.
          --blur-box <x1,y1,x2,y2>
                                 Visually blur a repeatable region; sidecars stay unchanged.
          --no-overwrite         Refuse to replace existing image/sidecar outputs
                                 (--no-clobber is also accepted).
          --window-title <text>  Title shown in the rendered window chrome.
          --filename <text>      Filename chip shown in the metadata header.
          --title <text>         Title shown in the metadata header.
          --caption <text>       Caption shown below the metadata title.
          --language-badge       Show the language badge in the metadata header.
          --line-numbers         Show the line-number gutter.
          --no-line-numbers      Hide the line-number gutter.
          --chrome / --no-chrome Show or hide the rendered window chrome.
          --shadow / --no-shadow Show or hide the rendered drop shadow.
          --highlight-lines <spec>
                                 Highlight 1-based lines/ranges (for example
                                 3,7-9,12).
          --redact-lines <spec>  Redact 1-based lines/ranges; sidecars replace
                                 them with [redacted].
          --redact-secrets       Scan for likely secrets and redact matching rows.
          --focus-lines / --no-focus-lines
                                 Dim or undim non-highlighted rows.
          --diff-bands / --no-diff-bands
                                 Show or hide GitHub-style diff line bands.
          --recursive            Batch only: include nested folders and preserve
                                 relative output paths.
          --fail-on-skipped      Batch only: exit non-zero if any file is skipped.
          --fail-on-empty        Batch only: exit non-zero when no files would render.
          --skipped-report <json>
                                 Batch only: write skipped files as a JSON report.
          --manifest <json>      Batch only: write rendered/planned outputs as JSON.
          --dry-run              Batch only: scan/load inputs without writing images.
          --include-ext <list>   Batch only: only render these comma-separated
                                 extensions (for example swift,md).
          --exclude-ext <list>   Batch only: ignore these comma-separated extensions
                                 before loading files.
          --text-sidecar         Also write a .txt next to --out with the source as
                                 selectable text (terminal escapes stripped).
          --markdown-sidecar     Also write a .md next to --out: the image reference
                                 plus the source in a fenced code block, ready to
                                 paste into a README or post.
          --html-sidecar         Also write a .html next to --out: the image embed
                                 plus escaped source in a <pre><code> block.
          --sidecars <list>      Enable sidecars by comma-separated list: text,
                                 markdown, html, or all.
          -h, --help             Show this help.

        Code rendering is fully local: it never needs the network, screen recording,
        or Accessibility permissions.
        """
}
