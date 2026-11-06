import SwiftUI
import VitrineRendering

/// What the clipboard holds, once its contents were measured. The row always keeps room for
/// two lines, so the empty state does not move when a measurement arrives.
///
/// It exists only while the document is empty and follows the clipboard only while its
/// window is key, so a window left in the background reads nothing and shows no old value.
/// The count is what a paste produces, so it follows the re-indent preference.
struct EmptyStageClipboardLine: View {
    @Environment(\.controlActiveState) private var activeState
    @State private var monitor: ClipboardMonitor

    init(reindentsOnPaste: Bool) {
        _monitor = State(
            initialValue: ClipboardMonitor(
                reader: .editorPaste(reindents: reindentsOnPaste), detectsWebURLs: false))
    }

    private var isFollowing: Bool { activeState == .key }

    var body: some View {
        let measured = isFollowing ? monitor.clipboard.measuredDescription() : nil
        Group {
            if let measured {
                Text("Clipboard holds \(Text(verbatim: measured).fontWeight(.semibold))")
            } else {
                Text(verbatim: " ")
            }
        }
        .font(.system(size: VitrineTokens.FontSize.caption))
        .foregroundStyle(VitrineTokens.Text.tertiary)
        .multilineTextAlignment(.center)
        .lineLimit(2, reservesSpace: true)
        .allowsHitTesting(false)
        .accessibilityHidden(measured == nil)
        .accessibilityIdentifier("empty-stage-clipboard")
        .onAppear { follow(isFollowing) }
        .onChange(of: isFollowing) { _, following in follow(following) }
        .onDisappear { monitor.stopWatching() }
    }

    private func follow(_ following: Bool) {
        if following {
            monitor.resumeWatching()
        } else {
            monitor.stopWatching()
        }
    }
}
