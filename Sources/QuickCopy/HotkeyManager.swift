import Cocoa
import CoreGraphics

/// Listens for the global ⌥⌘C hotkey via a `CGEventTap`, distinguishing a
/// single press (copy) from a double-tap within 400ms (paste).
///
/// - A single press fires `onCopy` immediately, with no artificial delay.
/// - A second press within `doubleTapInterval` fires `onPaste` *instead of*
///   copying again, so paste uses the clipboard captured by the first tap
///   rather than whatever sits under the cursor at the paste target.
final class HotkeyManager {

    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?

    /// When false, the tap stays installed (so the OS keeps trusting it) but
    /// hotkey presses are ignored.
    var isEnabled = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var lastPressTime: TimeInterval = 0
    private let doubleTapInterval: TimeInterval = 0.4

    /// 'c' on a US keyboard.
    private let keyCodeC: CGKeyCode = 8

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // The tap callback is a C function pointer and cannot capture context,
        // so `self` is threaded through via the refcon pointer.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("QuickCopy: failed to create event tap (is Accessibility granted?)")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the system disables the tap (timeout or user input), re-enable it
        // so the hotkey keeps working without a relaunch.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let isExactlyCommandOption =
            flags.contains(.maskCommand) &&
            flags.contains(.maskAlternate) &&
            !flags.contains(.maskControl) &&
            !flags.contains(.maskShift)

        guard keyCode == keyCodeC, isExactlyCommandOption else {
            return Unmanaged.passUnretained(event)
        }

        dispatch()
        // Consume the event so ⌥⌘C does not also reach the focused app.
        return nil
    }

    private func dispatch() {
        let now = ProcessInfo.processInfo.systemUptime
        let isDoubleTap = (now - lastPressTime) <= doubleTapInterval

        if isDoubleTap {
            // Reset so a third rapid press starts a fresh single-press cycle.
            lastPressTime = 0
            DispatchQueue.main.async { [weak self] in self?.onPaste?() }
        } else {
            lastPressTime = now
            DispatchQueue.main.async { [weak self] in self?.onCopy?() }
        }
    }
}
