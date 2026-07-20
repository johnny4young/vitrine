import Foundation

#if VITRINE_DIRECT_DOWNLOAD
    import Sparkle
#endif

/// The direct-download auto-update channel.
///
/// Vitrine's direct-download build (the signed, notarized DMG) updates itself with
/// [Sparkle](https://sparkle-project.org): it checks a signed EdDSA appcast and installs
/// the next build without a manual reinstall. The feed URL and the EdDSA public key live
/// in `Info.plist` (`SUFeedURL` / `SUPublicEDKey`); the private key lives only in the
/// release maintainer's Keychain (see `docs/RELEASING.md`).
///
/// ## Channel gating — the App Store build excludes Sparkle
///
/// Every Sparkle symbol is compiled only when `VITRINE_DIRECT_DOWNLOAD` is defined, which
/// the normal build sets (see `project.yml`). The optional Mac App Store build removes that
/// flag and strips the framework, so the App Store binary contains no Sparkle and no
/// update-check UI — the App Store owns its own update mechanism, and a third-party updater
/// is not permitted there. On that build this type still exists but degrades to a no-op:
/// `isSupported` is `false` and "Check for Updates" is hidden, so the rest of the app links
/// against a single, stable API regardless of channel.
///
/// ## Privacy — no analytics
///
/// The updater collects nothing. Sparkle's optional anonymous system-profiling feature stays
/// off (`SUEnableSystemProfiling` is absent/`NO` in `Info.plist`, and no profiling delegate
/// is installed), so an update check sends only the request needed to fetch the appcast and
/// the chosen download — no usage data, no identifiers, no telemetry. This keeps the
/// menu-bar app's on-device, account-less promise intact for the update path too.
@MainActor
final class SoftwareUpdater {
    /// The shared updater for the app's lifetime.
    static let shared = SoftwareUpdater()

    /// Whether this build ships the Sparkle updater. `true` on the direct-download build,
    /// `false` on the App Store build (which excludes Sparkle). UI that exposes "Check for
    /// Updates" hides the command when this is `false`.
    static var isSupported: Bool {
        #if VITRINE_DIRECT_DOWNLOAD
            return true
        #else
            return false
        #endif
    }

    #if VITRINE_DIRECT_DOWNLOAD
        /// Sparkle's standard controller. Created with `startingUpdater: true` so the
        /// background scheduler begins on first launch (subject to the user's consent prompt
        /// Sparkle shows once). No custom `updaterDelegate`/`userDriverDelegate` is supplied:
        /// the absence of a delegate is what guarantees no system-profiling hook and no
        /// telemetry — the updater only does the standard, user-visible check-and-install.
        private let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    private init() {}

    /// Begins a user-initiated update check, showing Sparkle's standard progress and
    /// "you're up to date" / "a new version is available" UI. A no-op on a build that
    /// excludes Sparkle (the App Store build), where the command is not surfaced anyway.
    func checkForUpdates() {
        #if VITRINE_DIRECT_DOWNLOAD
            controller.checkForUpdates(nil)
        #endif
    }
}
