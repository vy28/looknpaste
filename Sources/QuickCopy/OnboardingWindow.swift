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

        let trigger = HotkeySettings.trigger.displayName
        let body = NSTextField(wrappingLabelWithString: """
        QuickCopy reads whatever is under your mouse cursor and pastes on \
        demand. macOS requires Accessibility permission for an app to read \
        other apps' content and to send keystrokes. Copying images additionally \
        needs Screen Recording permission, requested the first time you hover \
        an image.

        Click the button below to open System Settings, then enable QuickCopy \
        in Privacy & Security → Accessibility. QuickCopy detects the change \
        automatically — no relaunch needed.

        Trigger key: \(trigger). Tap it over text/a link/an image to copy; tap \
        it over a text field to paste there — no click needed. Long-press to \
        copy a link's text instead of its URL. Change the trigger key any time \
        from the menu bar item.
        """)
        body.font = .systemFont(ofSize: 13)
        body.frame = NSRect(x: 24, y: 64, width: 412, height: 170)
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
