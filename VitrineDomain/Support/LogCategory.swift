/// The fixed set of unified-logging categories, and the subsystem they share.
///
/// This lives in the value layer because more than one module logs: the app's
/// `Log` and the rendering module's `RenderingLog` both build their loggers from
/// these cases. Declaring them once is what lets `DiagnosticsBundle` enumerate
/// `allCases` and truthfully say which streams it collects — with a per-module
/// copy, a category could exist in one module and be missing from that list, and
/// nothing would fail.
public enum LogCategory: String, CaseIterable, Sendable {
    /// The single subsystem every category shares. Matches the bundle identifier so
    /// the stream is easy to find (`log stream --subsystem com.johnny4young.vitrine`).
    public static let subsystem = "com.johnny4young.vitrine"

    /// App lifecycle (launch, hotkey wiring, termination).
    case app
    /// Quick-capture and file-input path: clipboard/file → render → clipboard/file,
    /// with no user content.
    case capture
    /// Canvas/render path. Also carries the render signposts that feed performance metrics.
    case render
    /// Image export to clipboard, file, or share sheet.
    case export
    /// Settings load, persistence, migration, and reset.
    case settings
}
