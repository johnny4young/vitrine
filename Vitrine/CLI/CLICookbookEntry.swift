/// The copyable commands the recipes card shows. Each line runs from a clone of this
/// repository, and `requiresPro` is pinned to the real gate by the CLI test suite.
struct CLICookbookEntry: Identifiable {
    enum ID: String { case validate, render, override, multiSize, terminal }

    let id: ID
    let lines: [String]
    let requiresPro: Bool

    private static let recipe = "docs/examples/documentation.vitrine-recipe.json"

    static var all: [CLICookbookEntry] {
        [
            CLICookbookEntry(
                id: .validate, lines: ["vitrine recipe validate \(recipe)"], requiresPro: false),
            CLICookbookEntry(
                id: .render,
                lines: ["vitrine render README.md --out readme.png --recipe \(recipe)"],
                requiresPro: true),
            CLICookbookEntry(
                id: .override,
                lines: [
                    "vitrine render README.md --recipe \(recipe) --theme dracula --out dracula.png"
                ],
                requiresPro: true),
            CLICookbookEntry(
                id: .multiSize,
                lines: [
                    "vitrine multi-size --git-staged --out out/"
                        + " --presets opengraph,twitter,instagram-story"
                ],
                requiresPro: true),
            CLICookbookEntry(
                id: .terminal, lines: ["vgrab htop", "vgrab -e npm test", "vpane -e"],
                requiresPro: false),
        ]
    }
}
