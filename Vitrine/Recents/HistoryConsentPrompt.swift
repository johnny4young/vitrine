import AppKit

/// A decision about history only, shown after the requested export has completed.
/// No suppression checkbox: consent applies only to this capture.
enum HistoryConsentPrompt {
    static func resolve(
        _ decision: CaptureRetentionPolicy.Decision
    ) -> CaptureRetentionPolicy.Consent {
        guard case .requiresConsent = decision else { return .doNotSave }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Save this capture in history?")
        alert.informativeText = String(
            localized:
                "This capture may contain a secret and has not been saved in history. Your export is unchanged. Sanitized history removes detected rows, but detection is not exhaustive. Keeping the original stores flagged text locally. Explicit redactions are always removed."
        )
        alert.addButton(withTitle: String(localized: "Don't Save"))
        alert.addButton(withTitle: String(localized: "Save Sanitized"))
        alert.addButton(withTitle: String(localized: "Keep Original"))
        // Escape is an explicit no-save action; no positive decision is the default.
        for (button, identifier) in zip(
            alert.buttons,
            [
                "history-consent-no-save", "history-consent-sanitized", "history-consent-original",
            ])
        {
            button.setAccessibilityIdentifier(identifier)
        }
        alert.buttons[0].keyEquivalent = "\u{1b}"
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = ""
        // Quick capture runs from a global hotkey while another app is frontmost; an
        // inactive agent app's modal would otherwise open behind it.
        NSApp.activate()
        alert.window.level = .modalPanel
        return choice(for: alert.runModal())
    }

    static func choice(for response: NSApplication.ModalResponse) -> CaptureRetentionPolicy.Consent
    {
        switch response {
        case .alertSecondButtonReturn: .saveSanitized
        case .alertThirdButtonReturn: .keepOriginal
        default: .doNotSave
        }
    }
}
