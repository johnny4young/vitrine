import OSLog
import Observation
import ServiceManagement
import SwiftUI

/// Wraps `SMAppService.mainApp` for "launch at login" — the modern
/// ServiceManagement API, not the deprecated `SMLoginItemSetEnabled`.
enum LaunchAtLogin {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        isEnabled(for: SMAppService.mainApp.status)
    }

    /// Pure mapping of a service status to an enabled flag (unit-testable).
    static func isEnabled(for status: SMAppService.Status) -> Bool {
        status == .enabled
    }

    /// The login-item operations, injectable so the switch's state rules are testable.
    struct Service {
        var status: () -> SMAppService.Status
        var register: () throws -> Void
        var unregister: () throws -> Void

        static let live = Service(
            status: { SMAppService.mainApp.status },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() })
    }
}

/// The launch-at-login switch state. It always shows the system's status after a
/// change, so a refused registration never leaves the switch on.
@Observable
final class LaunchAtLoginModel {
    private(set) var isOn = false
    /// The user turned the item off in System Settings, so registration needs approval.
    private(set) var requiresApproval = false
    private let service: LaunchAtLogin.Service

    init(service: LaunchAtLogin.Service = .live) {
        self.service = service
        refresh()
    }

    func refresh() {
        let status = service.status()
        isOn = LaunchAtLogin.isEnabled(for: status)
        requiresApproval = status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            let nsError = error as NSError
            Log.settings.error(
                "Launch-at-login update failed (\(nsError.domain, privacy: .public):\(nsError.code, privacy: .public))"
            )
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// The launch-at-login switch shared by Settings ▸ General and the Welcome window,
/// with the approval hint when System Settings blocks the login item.
struct LaunchAtLoginToggle: View {
    let model: LaunchAtLoginModel
    let title: LocalizedStringKey
    var hidesLabel = true
    let identifier: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            toggle
            if model.requiresApproval {
                Button("Approve in Login Items…") { model.openLoginItemsSettings() }
                    .buttonStyle(.link)
                    .font(.system(size: VitrineTokens.FontSize.caption))
                    .help("Vitrine is turned off in System Settings ▸ General ▸ Login Items.")
                    .accessibilityIdentifier("\(identifier)-approval")
            }
        }
        .onAppear { model.refresh() }
    }

    @ViewBuilder private var toggle: some View {
        let binding = Binding(get: { model.isOn }, set: { model.setEnabled($0) })
        if hidesLabel {
            Toggle(title, isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier(identifier)
        } else {
            Toggle(title, isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: VitrineTokens.FontSize.body))
                .accessibilityIdentifier(identifier)
        }
    }
}
