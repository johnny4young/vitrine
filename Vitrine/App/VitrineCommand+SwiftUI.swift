import AppKit
import SwiftUI

extension VitrineCommand {
    /// This command's AppKit `modifiers` translated into SwiftUI `EventModifiers`,
    /// so a toolbar/menu-bar button carries the exact modifier set its File-menu
    /// counterpart uses (CS-032). Kept separate from `swiftUIShortcut` because it
    /// is the drift-prone part — a dropped flag here is what would make ⇧⌘C decay
    /// to ⌘C in the toolbar — and, being a pure value mapping, it is unit-testable
    /// without constructing a `KeyboardShortcut` (whose initializer reaches the
    /// system Shortcuts daemon and hangs in a headless test host).
    var swiftUIEventModifiers: EventModifiers {
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        return eventModifiers
    }

    /// The SwiftUI `KeyboardShortcut` equivalent of this command's AppKit key and
    /// modifiers, so a toolbar button can bind the exact shortcut its File-menu
    /// counterpart uses (CS-032). `nil` when the command has no shortcut. Defined
    /// here, in a SwiftUI-importing file, to keep `VitrineCommands.swift` itself
    /// AppKit-only (it builds an `NSMenu`).
    var swiftUIShortcut: KeyboardShortcut? {
        guard let key = keyEquivalent, let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: swiftUIEventModifiers)
    }
}
