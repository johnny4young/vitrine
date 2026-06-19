import AppKit
import SwiftUI

/// The editor window, redesigned around presets (CS-037): a preset-first command
/// strip on top, then code on the left, a hero preview on a neutral stage in the
/// center, and a focused inspector on the right (CS-005/006/007/008/037).
///
/// ## Why this layout
///
/// Beautiful output should come from picking a strong preset first, not from
/// tweaking many sliders before seeing value. So the very first controls are the
/// destination/style presets (``PresetStripView``) and the primary export actions
/// (the window toolbar); the live preview gets visual priority in the center; and
/// the advanced style controls live behind progressive disclosure in
/// ``EditorInspectorView`` rather than crowding the canvas.
///
/// The view is large, so it is organized across focused extensions in sibling
/// files — `EditorView+Toolbar`, `EditorView+Stage`, `EditorView+Annotations`,
/// and `EditorView+DragDrop` — that share this type's stored state. Those state
/// properties are therefore module-internal (not `private`) so the extensions can
/// reach them; nothing outside `EditorView` references them.
struct EditorView: View {
    @EnvironmentObject var settings: AppSettings

    /// This window's editor session (CS-053). Each editor window has its own session
    /// (and therefore its own `settings` above), so a window can promote *its* style to
    /// the app-wide default without affecting the others. Injected by
    /// `EditorWindowController` when the window is created.
    @EnvironmentObject var session: EditorSession

    /// The saved-preset catalog and the custom-theme resolver, shared with the
    /// Settings panes so the editor and Preferences operate on the same data
    /// (CS-030/031). Held as observed singletons so the strip and inspector update
    /// live when presets or themes change anywhere in the app.
    @ObservedObject var presets = PresetStore.shared
    @ObservedObject var themes = CustomThemeStore.shared

    /// The PRO brand kit and entitlement, observed so the live preview shows (or
    /// drops) the watermark the moment the kit, the "apply to captures" switch, or
    /// the PRO state changes anywhere in the app (CS-092).
    @ObservedObject var brandKit = BrandKitStore.shared
    @ObservedObject var entitlements = Entitlements.shared

    /// True while a drag is hovering the editor, used to draw the drop affordance
    /// (CS-028).
    @State var isDropTargeted = false

    /// A binary/too-large/unreadable file the user tried to drop; presented as an
    /// alert so the rejection is clearly explained (CS-028).
    @State var dropError: FileInputLoader.LoadError?

    /// A successful load that is waiting on the user to choose replace vs. append,
    /// because the editor already has code (CS-028). `nil` when no decision is
    /// pending.
    @State var pendingDrop: PendingDrop?

    /// The natural (unscaled) size of the preview card, measured so the stage
    /// can scale it to always fit (design/handoff "scale-to-fit").
    @State var cardSize: CGSize = .zero

    /// The stage's current size, recorded so the capsule can report the live
    /// zoom percentage.
    @State var stageSize: CGSize = .zero

    /// The currently selected annotation, shared between the preview's interactive
    /// overlay and the inspector's annotation controls (CS-083). `nil` when nothing
    /// is selected. Editor-only UI state, not persisted.
    @State var selectedAnnotationID: UUID?

    /// The active annotation tool (CS-085). `.select` moves/resizes existing marks;
    /// any other tool puts the preview into draw mode. Editor-only UI state.
    @State var activeTool: AnnotationTool = .select

    /// The color and size the next drawn mark inherits. When a mark is selected, the
    /// toolbar edits *its* color/size instead (see `annotationStyleColor`).
    @State var newDrawColor: Color = Annotation.defaultColor.color
    @State var newDrawThickness: Double = Annotation.defaultThickness

    /// Undo/redo history for annotation edits (CS-086): each entry is a full snapshot
    /// of `config.annotations` captured just before a draw/move/resize/delete. Bounded
    /// so a long session never grows without limit.
    @State var annotationUndo: [[Annotation]] = []
    @State var annotationRedo: [[Annotation]] = []

    /// True while the save-style-preset prompt is up (the toolbar star).
    @State var showSavePresetPrompt = false
    @State var savePresetName = ""

    /// This editor's own `NSWindow`, captured via `WindowAccessor`, so actions like
    /// close-after-copy target it directly instead of guessing at `keyWindow`.
    @State var editorWindow: NSWindow?

    /// Which PRO multi-size sheet is up — the size picker when unlocked, the paywall
    /// when locked — or nil. A single `.sheet(item:)` drives both so they can never
    /// collide: two sibling `.sheet(isPresented:)` on one view can silently drop one
    /// (CS-093).
    @State var multiSizeSheet: MultiSizeSheet?

    /// The two mutually-exclusive multi-size sheets.
    enum MultiSizeSheet: String, Identifiable {
        case export, paywall
        var id: String { rawValue }
    }

    /// A loaded drop awaiting the user's replace-vs-append choice, kept so the
    /// confirmation dialog can apply exactly what was dropped.
    struct PendingDrop {
        var loaded: FileInputLoader.LoadedFile

        /// The dialog title names the source so the choice has context — the
        /// filename for a dropped file, or a generic label for dropped text.
        /// Localized through the String Catalog (CS-047); the filename is inserted
        /// into the localized template.
        var promptTitle: String {
            loaded.filename.isEmpty
                ? String(localized: "Add Dropped Text")
                : String(localized: "Load “\(loaded.filename)”")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            editorToolbar
            HStack(spacing: 0) {
                codeColumn
                    .frame(width: 280)
                previewStage
                inspectorColumn
                    .frame(width: 302)
            }
        }
        // Merge the toolbar into the title bar: the window is `fullSizeContentView`
        // with a hidden, transparent title bar, but SwiftUI still insets its content
        // below the title bar by default, leaving an empty strip above the toolbar.
        // Extending into the top safe area pulls the glass toolbar up to the window
        // edge, with the traffic lights floating over its leading 86 pt (CS-037).
        .ignoresSafeArea(.container, edges: .top)
        // A comfortable minimum that still fits the three columns on the smallest
        // supported window; the stage column absorbs all extra width.
        .frame(minWidth: 940, minHeight: 520)
        .background(WindowAccessor { editorWindow = $0 })
        .tint(VitrineTokens.Accent.system)
        .alert("Save Preset", isPresented: $showSavePresetPrompt) {
            TextField("Name", text: $savePresetName)
                .accessibilityIdentifier("editor-save-preset-name-field")
            Button("Save") {
                _ = presets.savePreset(named: savePresetName, from: settings.config)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Save the current style — theme, font, background, and the rest of your current layout — as a named preset."
            )
        }
        // No identifier on this root: the VStack is not an accessibility element,
        // so an identifier here would propagate down and *override* the nearest
        // descendant elements' identifiers (the preset strip would report the
        // root's name instead of `editor-preset-strip`), breaking the CS-037 and
        // CS-047 UI tests. The window itself is tagged `editor-window`.
        // A rejected file (binary, too large, unreadable) explains why in plain
        // language rather than failing silently (CS-028).
        .alert(
            "Can't Load That File",
            isPresented: Binding(
                get: { dropError != nil },
                set: { if !$0 { dropError = nil } })
        ) {
            Button("OK", role: .cancel) { dropError = nil }
        } message: {
            Text(dropError?.message ?? "")
        }
        // When the editor already has code, a drop asks before clobbering it:
        // replace everything, or append to the end (CS-028 "clear prompt").
        .confirmationDialog(
            pendingDrop?.promptTitle ?? "",
            isPresented: Binding(
                get: { pendingDrop != nil },
                set: { if !$0 { pendingDrop = nil } }),
            titleVisibility: .visible
        ) {
            // Replacing discards the entire current document, so it is marked
            // destructive (red) to distinguish it from the safe Append — matching
            // every other irreversible action in the app (CS-028).
            Button("Replace", role: .destructive) { applyDrop(replacing: true) }
            Button("Append") { applyDrop(replacing: false) }
            Button("Cancel", role: .cancel) { pendingDrop = nil }
        } message: {
            Text(
                "This editor already has code. Replace it with the dropped content, or append to the end?"
            )
        }
    }
}
