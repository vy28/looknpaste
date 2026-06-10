import Cocoa
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let textReader = TextReader()
    private let clipboard = ClipboardManager()
    private let hud = HUDWindow()
    private let onboarding = OnboardingWindow()

    private lazy var hotkeys = HotkeyManager()
    private lazy var hover = HoverTracker(textReader: textReader)

    private var statusItem: NSStatusItem?
    private var enableMenuItem: NSMenuItem?

    /// User-facing on/off toggle, independent of the permission state.
    private var isEnabled = true
    /// Whether the trackers have been wired up and started.
    private var isRunning = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        hotkeys.onCopy = { [weak self] in self?.performCopy() }
        hotkeys.onPaste = { [weak self] in self?.performPaste() }

        if AXIsProcessTrusted() {
            startServices()
        } else {
            onboarding.show()
        }
    }

    /// Re-check permission whenever the app is activated (e.g. the user returns
    /// after granting Accessibility) so no relaunch is required.
    func applicationDidBecomeActive(_ notification: Notification) {
        if AXIsProcessTrusted(), !isRunning {
            onboarding.close()
            startServices()
        }
        updateMenu()
    }

    // MARK: Services

    private func startServices() {
        guard !isRunning else { return }
        let tapStarted = hotkeys.start()
        guard tapStarted else {
            // Could not install the tap; surface onboarding again.
            onboarding.show()
            return
        }
        hover.start()
        isRunning = true
        applyEnabledState()
        updateMenu()
    }

    private func applyEnabledState() {
        hotkeys.isEnabled = isEnabled
        hover.isEnabled = isEnabled
        if !isEnabled {
            hover.reset()
        }
    }

    // MARK: Actions

    private func performCopy() {
        guard isEnabled else { return }
        let point = CGEvent(source: nil)?.location ?? .zero

        // A multi-word sweep wins; otherwise copy the single word/element.
        let text = hover.capturedTrail() ?? textReader.textUnderCursor(at: point)
        hover.reset()

        guard let text, !text.isEmpty else {
            hud.show("No text found")
            return
        }

        clipboard.copy(text)
        hud.show(text)
    }

    private func performPaste() {
        guard isEnabled else { return }
        guard let current = clipboard.currentString(), !current.isEmpty else { return }
        clipboard.paste()
    }

    // MARK: Status item & menu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "QuickCopy"
            ) {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "QC"
            }
        }

        let menu = NSMenu()

        let enableItem = NSMenuItem(
            title: "Enable QuickCopy",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enableItem.target = self
        menu.addItem(enableItem)
        enableMenuItem = enableItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit QuickCopy",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        updateMenu()
    }

    private func updateMenu() {
        let trusted = AXIsProcessTrusted()
        enableMenuItem?.state = (isEnabled && isRunning) ? .on : .off
        enableMenuItem?.isEnabled = trusted
        enableMenuItem?.title = trusted ? "Enable QuickCopy" : "Enable QuickCopy (needs Accessibility)"
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        applyEnabledState()
        updateMenu()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
