import AppKit
import Carbon.HIToolbox
import Combine
import KeyboardShortcuts
import SwiftUI

/// A clash the app can actually detect. macOS has no API that lists another app's
/// global hotkeys, so neither case can ever name one.
enum HotkeyConflict: Equatable {
    case macOSShortcut
    case menuCommand(title: String)

    /// The recorder's own checks, in its order, for a shortcut that is already stored.
    /// It warns only while recording, so an older assignment or a later change to
    /// System Settings would otherwise go unreported.
    static func find(
        for shortcut: KeyboardShortcuts.Shortcut,
        systemShortcuts: [KeyboardShortcuts.Shortcut],
        mainMenu: NSMenu?,
        acknowledged: KeyboardShortcuts.Shortcut? = nil
    ) -> HotkeyConflict? {
        if let mainMenu, let title = menuCommandTitle(for: shortcut, in: mainMenu) {
            return .menuCommand(title: title)
        }
        // The recorder accepts a bare F12 without warning, so it is not reported here either.
        if shortcut != .init(.f12), shortcut != acknowledged, systemShortcuts.contains(shortcut) {
            return .macOSShortcut
        }
        return nil
    }

    private static func menuCommandTitle(
        for shortcut: KeyboardShortcuts.Shortcut, in menu: NSMenu
    ) -> String? {
        for item in menu.items {
            var key = item.keyEquivalent
            var modifiers = item.keyEquivalentModifierMask
            // AppKit also spells ⇧ as an uppercase key equivalent.
            if shortcut.modifiers.contains(.shift), key.lowercased() != key {
                key = key.lowercased()
                modifiers.insert(.shift)
            }
            if shortcut.nsMenuItemKeyEquivalent == key, shortcut.modifiers == modifiers {
                return item.title
            }
            if let submenu = item.submenu,
                let title = menuCommandTitle(for: shortcut, in: submenu)
            {
                return title
            }
        }
        return nil
    }

    /// The shortcuts enabled in System Settings › Keyboard › Keyboard Shortcuts. The
    /// system reports their keys only, not what each one does.
    static var enabledSystemShortcuts: [KeyboardShortcuts.Shortcut] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
            let entries = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return entries.compactMap { entry in
            guard entry[kHISymbolicHotKeyEnabled] as? Bool == true,
                let code = entry[kHISymbolicHotKeyCode] as? Int,
                let modifiers = entry[kHISymbolicHotKeyModifiers] as? Int
            else { return nil }
            return KeyboardShortcuts.Shortcut(carbonKeyCode: code, carbonModifiers: modifiers)
        }
    }
}

/// The hotkey recorder and, under it, any clash with the shortcut it holds.
struct GlobalHotkeySettingsRows: View {
    var settings: AppSettings
    @State private var recorder = HotkeyRecorderHandle()
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .quickCapture)
    @State private var conflict: HotkeyConflict?

    var body: some View {
        TokenRow(label: Text("Global hotkey"), caption: Text("shortcut.scope.help")) {
            HotkeyRecorderField(handle: recorder) { settings.noteRecordedHotkey($0) }
                .accessibilityLabel("Global hotkey")
                .accessibilityIdentifier("settings-hotkey-recorder")
        }
        .onAppear(perform: refresh)
        // Help and Welcome have their own recorders, and the stored value lives in the
        // standard defaults. Defaults can post from any thread.
        .onReceive(
            NotificationCenter.default
                .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
                .receive(on: DispatchQueue.main)
        ) { _ in
            if KeyboardShortcuts.getShortcut(for: .quickCapture) != shortcut { refresh() }
        }
        // Coming back from System Settings, where a macOS shortcut may have changed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            _ in refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenu.didInstallNotification)) {
            _ in refresh()
        }
        .onChange(of: settings.acknowledgedMacOSHotkey) { refresh() }

        if let shortcut, let conflict {
            TokenRow(label: conflictMessage(conflict, shortcut: shortcut)) {
                Button("Change…") { recorder.beginRecording() }
                    .buttonStyle(.bordered)
                    .fixedSize()
                    .accessibilityIdentifier("settings-hotkey-change-button")
            }
            .accessibilityContainerIdentifier("settings-hotkey-conflict")
        }
    }

    private func conflictMessage(
        _ conflict: HotkeyConflict, shortcut: KeyboardShortcuts.Shortcut
    ) -> Text {
        switch conflict {
        case .macOSShortcut:
            Text("Conflict: \(shortcut.description) is also a macOS shortcut")
        case .menuCommand(let title):
            Text("Conflict: \(shortcut.description) is also the menu command “\(title)”")
        }
    }

    private func refresh() {
        let current = KeyboardShortcuts.getShortcut(for: .quickCapture)
        shortcut = current
        conflict = current.flatMap {
            HotkeyConflict.find(
                for: $0, systemShortcuts: HotkeyConflict.enabledSystemShortcuts,
                mainMenu: NSApp.mainMenu, acknowledged: settings.acknowledgedMacOSHotkey)
        }
    }
}

/// Lets a control outside the recorder start recording, which the package's SwiftUI
/// `Recorder` has no way to do.
final class HotkeyRecorderHandle {
    weak var field: KeyboardShortcuts.RecorderCocoa?

    func beginRecording() {
        guard let field else { return }
        field.window?.makeFirstResponder(field)
    }
}

/// The package's `RecorderCocoa`, hosted the way its `Recorder` does but reachable
/// through a handle.
private struct HotkeyRecorderField: NSViewRepresentable {
    let handle: HotkeyRecorderHandle
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let field = KeyboardShortcuts.RecorderCocoa(for: .quickCapture, onChange: onChange)
        handle.field = field
        return field
    }

    func updateNSView(_ field: KeyboardShortcuts.RecorderCocoa, context: Context) {
        handle.field = field
    }
}
