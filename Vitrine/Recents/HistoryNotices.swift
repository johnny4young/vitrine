import SwiftUI

/// Shared recovery and privacy controls for Settings and the history gallery.
/// Every destructive action is explicit; disabling history is not a purge.
struct HistoryNotices: View {
    @Bindable var recents: RecentsStore
    @State private var confirmsRecovery = false
    @State private var confirmsPurge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recents.needsRecovery {
                Text("History needs recovery")
                    .font(.headline)
                Text(
                    "The original history and previews have been preserved. New captures are not saved until you recover valid entries or delete the damaged history."
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("Recover Valid Captures") { confirmsRecovery = true }
                    .disabled(recents.captures.isEmpty)
                    .accessibilityIdentifier("history-recover")
            }
            if recents.hasLegacyHistory {
                Text(
                    "Older history may contain sensitive text or previews. Keeping it does not sanitize it. You can delete it here; backups and copies outside Vitrine are not erased."
                )
                .fixedSize(horizontal: false, vertical: true)
                Button("Keep Existing History") { recents.acknowledgeLegacyHistory() }
                    .accessibilityIdentifier("history-keep-existing")
            }
            Button("Delete History and Cached Previews…", role: .destructive) {
                confirmsPurge = true
            }
            .accessibilityIdentifier("history-purge")
        }
        .confirmationDialog(
            "Recover history?", isPresented: $confirmsRecovery, titleVisibility: .visible
        ) {
            Button("Recover Valid Captures") { recents.recoverAvailableCaptures() }
                .accessibilityIdentifier("history-confirm-recover")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This replaces the damaged archive with its readable captures. Unreadable entries will be discarded. Cancel keeps the original archive unchanged."
            )
        }
        .confirmationDialog(
            "Delete all history?", isPresented: $confirmsPurge, titleVisibility: .visible
        ) {
            Button("Delete All History", role: .destructive) { recents.clear() }
                .accessibilityIdentifier("history-confirm-purge")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This deletes every capture, including pinned captures, and cached previews from Vitrine. It does not erase backups or copies outside the app."
            )
        }
    }
}
