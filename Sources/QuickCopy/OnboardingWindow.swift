import Cocoa

/// First-launch window explaining the Accessibility requirement, with a button
/// that deep-links to System Settings → Privacy & Security → Accessibility.
final class OnboardingWindow {

    private var window: NSWindow?

    private let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuickCopy"
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "Enable Accessibility for QuickCopy")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.frame = NSRect(x: 24, y: 244, width: 412, height: 28)
        title.autoresizingMask = [.width, .minYMargin]

        let body = NSTextField(wrappingLabelWithString: """
        QuickCopy reads the text under your mouse cursor and pastes on demand. \
        macOS requires Accessibility permission for an app to read other apps' \
        content and to send keystrokes.

        Click the button below to open System Settings, then enable QuickCopy \
        in Privacy & Security → Accessibility. QuickCopy detects the change \
        automatically — no relaunch needed.

        Hotkey: ⌥⌘C copies the word under the cursor. Tap it twice quickly to \
        paste at the keyboard-focused location.
        """)
        body.font = .systemFont(ofSize: 13)
        body.frame = NSRect(x: 24, y: 84, width: 412, height: 150)
        body.autoresizingMask = [.width, .height]

        let openButton = NSButton(
            title: "Open Accessibility Settings",
            target: self,
            action: #selector(openSettings)
        )
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "\r"
        openButton.frame = NSRect(x: 24, y: 24, width: 240, height: 32)
        openButton.autoresizingMask = [.maxXMargin, .maxYMargin]

        content.addSubview(title)
        content.addSubview(body)
        content.addSubview(openButton)
        window.contentView = content

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    @objc private func openSettings() {
        NSWorkspace.shared.open(accessibilityURL)
    }
}
