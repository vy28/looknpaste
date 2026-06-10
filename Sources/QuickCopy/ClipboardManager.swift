import Cocoa

/// Thin wrapper around `NSPasteboard` plus a helper to synthesize a ⌘V paste.
final class ClipboardManager {

    private let pasteboard = NSPasteboard.general

    /// 'v' on a US keyboard. Paste is performed by simulating ⌘V so the
    /// frontmost (keyboard-focused) app receives a normal paste command.
    private let keyCodeV: CGKeyCode = 9

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func currentString() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Simulate ⌘V at the current keyboard-focus location.
    ///
    /// Flags are set explicitly to `.maskCommand` so any modifiers the user
    /// may still be holding from the hotkey (⌥) do not leak into the synthetic
    /// event. The events are posted to the annotated session tap so they are
    /// delivered to the focused application like real key presses.
    func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
