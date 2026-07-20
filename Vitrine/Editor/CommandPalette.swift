import SwiftUI

/// One action the command palette can run: a titled, keyword-tagged command that
/// fuzzy-search surfaces and Return executes.
///
/// The palette is the fast path over the editor's controls — apply a theme, toggle a
/// style, jump to an export — without hunting through the inspector's panes. Each
/// command is a value with a closure, so the list is built declaratively at the call
/// site and the matcher below stays pure.
struct EditorCommand: Identifiable {
    let id: String
    /// The label shown in the list and the primary match target.
    let title: String
    /// A short group label shown trailing (e.g. "Theme", "Export"), so two commands
    /// with similar titles read distinctly.
    let group: String
    /// Extra terms that should surface the command even when they aren't in the title
    /// (e.g. "dark" for a dark theme, "png" for copy-image). Never shown.
    let keywords: [String]
    /// An SF Symbol shown leading.
    let symbol: String
    /// Run the command. The palette closes first, then invokes this on the main actor.
    let run: () -> Void

    init(
        id: String, title: String, group: String, keywords: [String] = [],
        symbol: String, run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.keywords = keywords
        self.symbol = symbol
        self.run = run
    }

    /// Searchable title, group, and keywords with locale-aware case and diacritic
    /// folding applied.
    var searchTargets: [String] {
        ([title, group] + keywords).map(CommandPaletteFilter.foldForSearch)
    }
}

/// The palette's search — pure so its ranking is unit-testable without a view.
///
/// Matching is a case-insensitive **subsequence** test (the classic fuzzy-finder
/// rule: "clr" matches "Clear"), scored so the most direct matches lead:
/// a title prefix beats a title word-start beats a title substring beats a
/// subsequence, and any title match beats a keyword-only match. Ties keep the input
/// order, so a given catalog + query always ranks identically.
enum CommandPaletteFilter {
    /// Ranks `commands` for `query`. An empty/whitespace query returns the catalog
    /// unchanged (the palette opens showing everything in author order); otherwise
    /// only matching commands are returned, best first.
    static func rank(_ commands: [EditorCommand], query: String) -> [EditorCommand] {
        let needle = foldForSearch(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return commands }

        return
            commands
            .enumerated()
            .compactMap { index, command -> (score: Int, order: Int, command: EditorCommand)? in
                guard let score = bestScore(for: command, needle: needle) else { return nil }
                return (score, index, command)
            }
            // Higher score first; ties fall back to author order (stable).
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.order < rhs.order
            }
            .map(\.command)
    }

    static func foldForSearch(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// The best score of `needle` against any of a command's search targets, or `nil`
    /// when it matches none. The title (target 0) and group (target 1) score higher
    /// than a keyword (target ≥ 2), so a keyword-only hit never outranks a title hit.
    private static func bestScore(for command: EditorCommand, needle: String) -> Int? {
        var best: Int?
        for (targetIndex, target) in command.searchTargets.enumerated() {
            guard let base = matchScore(needle: needle, in: target) else { continue }
            // Title/group hits get the full weight; keyword hits are demoted so they
            // only surface a command the title couldn't.
            let weight = targetIndex <= 1 ? base : base / 10
            best = max(best ?? 0, weight)
        }
        return best
    }

    /// Scores `needle` against a single `haystack`, or `nil` if it isn't even a
    /// subsequence. The tiers are spaced by 100 so the per-target keyword demotion
    /// (÷10) can never lift a keyword match above a title match of the same tier.
    private static func matchScore(needle: String, in haystack: String) -> Int? {
        if haystack.hasPrefix(needle) { return 400 }
        if wordStarts(of: haystack).contains(where: { $0.hasPrefix(needle) }) { return 300 }
        if haystack.contains(needle) { return 200 }
        if isSubsequence(needle, of: haystack) { return 100 }
        return nil
    }

    /// The substrings of `haystack` that begin a word — split on spaces and hyphens —
    /// so "line" word-start-matches "Show line numbers".
    private static func wordStarts(of haystack: String) -> [Substring] {
        haystack.split { $0 == " " || $0 == "-" }
    }

    /// Whether every character of `needle` appears in `haystack` in order (the fuzzy
    /// rule). Both are already lowercased by the caller.
    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var haystackIndex = haystack.startIndex
        for character in needle {
            guard let found = haystack[haystackIndex...].firstIndex(of: character) else {
                return false
            }
            haystackIndex = haystack.index(after: found)
        }
        return true
    }
}

/// The ⌘K command palette overlay: a focused search field over a live filtered list of
/// `EditorCommand`s. Type to filter, ↑/↓ to move, Return to run,
/// Escape (or a click outside) to dismiss. The ranking is `CommandPaletteFilter`;
/// this view is only the presentation and keyboard handling.
struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let commands: [EditorCommand]

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var results: [EditorCommand] {
        CommandPaletteFilter.rank(commands, query: query)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // A dimmed scrim; a click anywhere outside the panel dismisses.
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            panel
                .padding(.top, 96)
        }
        // `.contain` keeps the field/rows identifiers reachable under the root id — an
        // id on the bare ZStack propagates down and clobbers them (the same
        // SwiftUI gotcha as the export sheets; here it hid `command-palette-field`
        // from the UI smoke on CI while the palette itself rendered fine).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("command-palette")
        .onAppear {
            selection = 0
            fieldFocused = true
        }
        // Clamp the selection whenever the result set shrinks under the cursor.
        .onChange(of: query) { _, _ in selection = 0 }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: VitrineTokens.FontSize.body))
                    .focused($fieldFocused)
                    .onSubmit(runSelection)
                    .accessibilityIdentifier("command-palette-field")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if results.isEmpty {
                Text("No matching commands")
                    .font(.system(size: VitrineTokens.FontSize.subhead))
                    .foregroundStyle(VitrineTokens.Text.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) {
                                index, command in
                                Button {
                                    run(command)
                                } label: {
                                    row(command, isSelected: index == selection)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("command-palette-command-\(command.id)")
                                .id(index)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection) { _, new in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(new, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 520)
        .background(VitrineTokens.Surface.window)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(VitrineTokens.Line.border)
        )
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        // Arrow keys move the selection; Escape dismisses. Return is handled by the
        // field's onSubmit so a selection runs even while the field holds focus.
        .onKeyPress(.downArrow) {
            move(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            move(-1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
    }

    private func row(_ command: EditorCommand, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 13))
                .frame(width: 20)
                .foregroundStyle(
                    isSelected ? VitrineTokens.Text.primary : VitrineTokens.Text.secondary)
            Text(command.title)
                .font(.system(size: VitrineTokens.FontSize.body))
                .foregroundStyle(VitrineTokens.Text.primary)
            Spacer(minLength: 8)
            Text(command.group)
                .font(.system(size: VitrineTokens.FontSize.caption))
                .foregroundStyle(VitrineTokens.Text.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? VitrineTokens.Accent.system.opacity(0.22) : .clear)
        )
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    private func runSelection() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    private func run(_ command: EditorCommand) {
        dismiss()
        command.run()
    }

    private func dismiss() {
        isPresented = false
    }
}
