import Foundation

/// One cell of a reconstructed terminal screen and the SGR style it was drawn with. A
/// blank cell is a space in the default style.
public struct TerminalCell: Equatable, Sendable {
    /// What occupies the cell: a grapheme — a base scalar plus any combining marks — or
    /// the right half of a wide (double-width) character to its left, a placeholder that
    /// owns no glyph and is never emitted (the head to its left carries the text).
    public enum Content: Equatable, Sendable {
        case grapheme(String)
        case continuation
    }

    public var content: Content
    public var style: ANSIStyle

    /// An empty cell — a space with no styling.
    public static let blank = TerminalCell(content: .grapheme(" "), style: ANSIStyle())

    /// Whether the cell is an unstyled space, i.e. nothing was drawn here. Trailing
    /// blanks are trimmed when the screen is flattened into runs. A continuation cell is
    /// never blank: its head to the left is live content.
    public var isBlank: Bool {
        guard case .grapheme(" ") = content else { return false }
        return style == ANSIStyle()
    }
}

/// A cell-buffer VT emulator: replays a stream of terminal output that addresses the
/// screen with cursor-positioning escapes (CUP, erase, scrolling, alternate screen) and
/// reports the **final** screen state.
///
/// This is the grid counterpart to ``ANSIRenderer/normalize(_:)``, which is
/// line-oriented and strips cursor moves: where line mode captures the scrolled
/// transcript (a `git log`, a test run), the grid captures the screen a full-screen
/// TUI — `htop`, `vim`, `lazygit`, or a pager like `less`/`man` — paints by writing
/// cells directly. Pure and AppKit-free for unit-testing, like ``ANSIParser``: it
/// produces `[ANSIRun]` that ``ANSIRenderer`` turns into the image, reusing ``ANSIStyle``
/// and ``ANSIParser/applySGR(_:to:)`` for the pen so the styling matches line mode.
///
/// The screen is a **fixed height** (`screenRows`, inferred from the stream): a line feed
/// at the bottom margin *scrolls* the screen up instead of growing the buffer, which is
/// what a real terminal does and what pagers (`less`, `man`, `bat`) rely on — they write
/// from the bottom line and let `\n` scroll. A growing buffer would stack the whole file
/// with the content stranded at the bottom.
///
/// Handles: cursor positioning (CUP/CUU-D/CUF-B/CHA/VPA/CNL/CPL, CR/LF/BS/HT), erase
/// (ED/EL), SGR, autowrap, OSC 8 hyperlinks, save/restore cursor, the alternate-screen
/// snapshot that makes `htop`/`vim` capturable, charset-designation escapes, and **scroll
/// regions** (DECSTBM) with scroll-up/down (SU/SD), insert/delete-line (IL/DL),
/// character insert/delete/erase (ICH/DCH/ECH), reverse-index / index / next-line
/// (RI/IND/NEL), and **wide (double-width CJK/emoji) characters** plus combining marks
/// (via ``CharacterWidth``), which advance the cursor by 2 and 0 columns respectively.
public struct TerminalScreen: Sendable {
    /// The width the stream was produced at: cursor columns clamp to it and printed text
    /// autowraps at it.
    public let columns: Int
    /// The fixed screen height. The grid is always exactly this many rows; a line feed at
    /// the scroll-region bottom scrolls rather than adding a row.
    public let screenRows: Int

    /// The visible buffer — always `screenRows` rows tall; each row grows to its longest
    /// written column. The primary screen, or the alternate screen while in it.
    var rows: [[TerminalCell]]
    var cursorRow = 0
    var cursorCol = 0
    /// Real terminals delay autowrap until the next printable character. Keeping that
    /// pending state avoids double-advancing when a full-width line is followed by `\n`.
    var pendingWrap = false
    /// The current pen, accumulated from SGR codes (and the OSC 8 link, which rides on the
    /// style so each cell remembers its hyperlink).
    var style = ANSIStyle()
    var saved: (row: Int, col: Int, pendingWrap: Bool, style: ANSIStyle)?
    /// The scroll region (DECSTBM), inclusive 0-based row bounds. Defaults to the whole
    /// screen; a line feed at `scrollBottom` scrolls `[scrollTop, scrollBottom]` up.
    var scrollTop = 0
    var scrollBottom = 0

    /// While on the alternate screen the primary buffer (and its cursor / scroll region)
    /// is stashed here; `nil` on the primary screen.
    var primaryStash:
        (
            rows: [[TerminalCell]], row: Int, col: Int, pendingWrap: Bool, top: Int, bottom: Int
        )?
    /// The last full alternate-screen frame, captured when the program *leaves* the alt
    /// screen (its exit) — the htop/vim screen the user saw, which the restored primary
    /// screen's shell prompt would otherwise hide.
    var capturedAltFrame: [[TerminalCell]]?
    /// A fallback alt-screen frame snapshotted just before an in-alt full clear: some apps
    /// (`nvim`, `lazygit`) erase the screen *before* leaving the alt buffer on exit, which
    /// would otherwise blank the frame we capture.
    var altSnapshot: [[TerminalCell]]?

    public init(columns: Int = 80, rows screenRows: Int = 200) {
        self.columns = max(1, columns)
        self.screenRows = max(1, min(screenRows, 1000))
        self.rows = Array(repeating: [], count: self.screenRows)
        self.scrollBottom = self.screenRows - 1
    }
}
