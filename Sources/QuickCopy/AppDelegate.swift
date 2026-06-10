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
    private var triggerMenuItems: [TriggerKey: NSMenuItem] = [:]

    /// User-facing on/off toggle, independent of the permission state.
    private var isEnabled = true
    /// Whether the trackers have been wired up and started.
    private var isRunning = false
    /// Polls the Accessibility trust state until granted, since an accessory
    /// app is not reliably reactivated when the user returns from Settings.
    private var permissionPollTimer: Timer?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        hotkeys.onShortTap = { [weak self] in self?.performShortTap() }
        hotkeys.onLongPress = { [weak self] in self?.performLongPress() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeyDidChange),
            name: HotkeySettings.didChangeNotification,
            object: nil
        )

        if AXIsProcessTrusted() {
            startServices()
        } else {
            onboarding.show()
            startPermissionPolling()
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

    // MARK: Permission polling

    /// An accessory (menu bar) app does not reliably receive
    /// `applicationDidBecomeActive` when the user grants Accessibility in
    /// System Settings, so poll the trust state until it flips on.
    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if AXIsProcessTrusted() {
                self.onboarding.close()
                self.startServices()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    // MARK: Services

    private func startServices() {
        guard !isRunning else { return }
        let tapStarted = hotkeys.start()
        guard tapStarted else {
            // Could not install the tap; the grant may not have propagated to
            // this process yet — keep polling and keep onboarding visible.
            onboarding.show()
            startPermissionPolling()
            return
        }
        stopPermissionPolling()
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

    /// Short tap: context-aware. Priority is
    ///   swept phrase → paste-into-field → open-URL-in-new-tab → link URL →
    ///   image → single word/element.
    private func performShortTap() {
        guard isEnabled else { return }
        let point = CGEvent(source: nil)?.location ?? .zero

        // A multi-word sweep wins: it reflects exactly what the user read over.
        if let trail = hover.capturedTrail() {
            hover.reset()
            clipboard.copy(trail)
            hud.show(trail)
            return
        }
        hover.reset()

        // Over an editable field → paste right there, no click needed.
        if let field = textReader.editableElement(at: point) {
            pasteInto(field)
            return
        }

        // Over a browser's "+" new-tab button while a URL is on the clipboard
        // → open that URL in a new tab.
        if let url = clipboard.currentURL(), textReader.isNewTabButton(at: point) {
            NSWorkspace.shared.open(url)
            hud.show("Opened \(url.absoluteString)")
            return
        }

        // Over a link → copy its URL. (Long-press a linked image to grab the
        // image instead.)
        if let url = textReader.linkURL(at: point) {
            clipboard.copy(url.absoluteString)
            hud.show(url.absoluteString)
            return
        }

        // Fall back to the single word/element under the cursor.
        copyTextUnderCursor(at: point)
    }

    /// Long press: grab the "whole thing" under the cursor. Over an image this
    /// copies the image; over text it copies the entire element/block (or a
    /// link's full visible text rather than its URL).
    private func performLongPress() {
        guard isEnabled else { return }
        let point = CGEvent(source: nil)?.location ?? .zero
        hover.reset()

        // Over an image → copy the image itself.
        if let frame = textReader.imageFrame(at: point) {
            copyImage(frame: frame)
            return
        }

        // Otherwise copy the whole text block under the cursor.
        if let full = textReader.fullElementText(at: point), !full.isEmpty {
            clipboard.copy(full)
            hud.show(full)
            return
        }

        copyTextUnderCursor(at: point)
    }

    private func copyTextUnderCursor(at point: CGPoint) {
        guard let text = textReader.textUnderCursor(at: point), !text.isEmpty else {
            hud.show("No text found")
            return
        }
        clipboard.copy(text)
        hud.show(text)
    }

    private func copyImage(frame: CGRect) {
        guard ScreenCapture.hasPermission() else {
            hud.show("Enable Screen Recording for image copy")
            ScreenCapture.requestPermission()
            ScreenCapture.openSettings()
            return
        }

        guard let image = ScreenCapture.capture(rect: frame) else {
            hud.show("Couldn't copy image")
            return
        }

        clipboard.copyImage(image)
        hud.showImage(image)
    }

    /// Focuses the field under the cursor and pastes into it without a click.
    private func pasteInto(_ field: AXUIElement) {
        guard let current = clipboard.currentString(), !current.isEmpty else {
            hud.show("Clipboard is empty")
            return
        }

        let pid = textReader.focus(field)
        // Bring the field's app frontmost so the synthesized ⌘V is delivered
        // there, then paste after a short beat for the activation to land.
        if let pid, let app = NSRunningApplication(processIdentifier: pid), !app.isActive {
            app.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.clipboard.paste()
            }
        } else {
            clipboard.paste()
        }
        hud.show("Pasted")
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

        let triggerItem = NSMenuItem(title: "Trigger Key", action: nil, keyEquivalent: "")
        let triggerSubmenu = NSMenu()
        for key in TriggerKey.allCases {
            let item = NSMenuItem(
                title: key.displayName,
                action: #selector(selectTriggerKey(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = key.rawValue
            triggerSubmenu.addItem(item)
            triggerMenuItems[key] = item
        }
        triggerItem.submenu = triggerSubmenu
        menu.addItem(triggerItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let screenRecordingItem = NSMenuItem(
            title: "Enable Image Copy (Screen Recording)…",
            action: #selector(requestScreenRecording),
            keyEquivalent: ""
        )
        screenRecordingItem.target = self
        menu.addItem(screenRecordingItem)

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

        let current = HotkeySettings.trigger
        for (key, item) in triggerMenuItems {
            item.state = (key == current) ? .on : .off
        }
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        applyEnabledState()
        updateMenu()
    }

    @objc private func hotkeyDidChange() {
        updateMenu()
    }

    @objc private func selectTriggerKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = TriggerKey(rawValue: raw) else { return }
        HotkeySettings.trigger = key
        updateMenu()
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func requestScreenRecording() {
        if ScreenCapture.hasPermission() {
            hud.show("Image copy is already enabled")
            return
        }
        // Triggering the request is what registers QuickCopy in the Screen
        // Recording list and shows the system prompt; merely opening Settings
        // does not. Then open the pane so the user can flip the toggle.
        ScreenCapture.requestPermission()
        ScreenCapture.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
