import Cocoa
import CoreGraphics

/// Recognizes a lone tap of the configured trigger modifier (default Option)
/// via a `CGEventTap`, distinguishing a short tap from a long press.
///
/// The trigger key is *observed, never consumed*, so it keeps working normally
/// for typing and shortcuts. A gesture only fires when the trigger is pressed
/// and released cleanly — if any other key, mouse click, scroll, or extra
/// modifier happens while it is held, the gesture is cancelled. This keeps
/// Option+click, Option+letter (special characters), ⌘⌥-combos, etc. working
/// untouched.
///
/// - A short tap (released before `longPressThreshold`) fires `onShortTap`.
/// - Holding past `longPressThreshold` fires `onLongPress` immediately (so the
///   user gets feedback and can release), and the subsequent release does not
///   also fire a short tap.
final class HotkeyManager {

    var onShortTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    /// When false, the tap stays installed (so the OS keeps trusting it) but
    /// gestures are ignored.
    var isEnabled = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let longPressThreshold: TimeInterval = 0.35

    private var triggerWasDown = false
    private var gestureActive = false
    private var longFired = false
    private var longPressWork: DispatchWorkItem?

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let eventTypes: [CGEventType] = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
        ]
        var mask: CGEventMask = 0
        for type in eventTypes {
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }

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
        cancelGesture()
    }

    // MARK: Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // If the system disables the tap (timeout or user input), re-enable it
        // so the trigger keeps working without a relaunch.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else { return Unmanaged.passUnretained(event) }

        let triggerFlag = HotkeySettings.trigger.flag
        let allModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let otherModifiers = event.flags.intersection(allModifiers).subtracting(triggerFlag)

        switch type {
        case .flagsChanged:
            let triggerNow = event.flags.contains(triggerFlag)
            if triggerNow && !triggerWasDown {
                // Trigger just went down. Only begin a gesture if it is the
                // sole modifier — a combo (e.g. ⌘⌥) is not a trigger tap.
                if otherModifiers.isEmpty {
                    beginGesture()
                }
            } else if !triggerNow && triggerWasDown {
                endGesture()
            } else if triggerNow && triggerWasDown {
                // Still held but another modifier toggled → it's a combo now.
                cancelGesture()
            }
            triggerWasDown = triggerNow

        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
            // Any other input while the trigger is held means the user is doing
            // something else (Option+click, typing a special character, etc.).
            if gestureActive { cancelGesture() }

        default:
            break
        }

        // Never consume the event: the trigger key must keep working normally.
        return Unmanaged.passUnretained(event)
    }

    // MARK: Gesture state machine

    private func beginGesture() {
        gestureActive = true
        longFired = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.gestureActive else { return }
            self.longFired = true
            self.onLongPress?()
        }
        longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressThreshold, execute: work)
    }

    private func endGesture() {
        longPressWork?.cancel()
        longPressWork = nil
        let shouldFireShort = gestureActive && !longFired
        gestureActive = false
        if shouldFireShort {
            DispatchQueue.main.async { [weak self] in self?.onShortTap?() }
        }
    }

    private func cancelGesture() {
        longPressWork?.cancel()
        longPressWork = nil
        gestureActive = false
    }
}
