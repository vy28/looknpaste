import Cocoa
import CoreGraphics

/// The modifier key whose lone tap triggers QuickCopy. QuickCopy *observes*
/// this key rather than consuming it, so it keeps working normally for typing
/// and shortcuts — only a clean tap (pressed and released with no other key,
/// click, or scroll in between) fires an action.
enum TriggerKey: String, CaseIterable {
    case option
    case control
    case command
    case shift

    var displayName: String {
        switch self {
        case .option: return "Option (⌥)"
        case .control: return "Control (⌃)"
        case .command: return "Command (⌘)"
        case .shift: return "Shift (⇧)"
        }
    }

    /// The CGEvent flag bit corresponding to this modifier.
    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        case .shift: return .maskShift
        }
    }
}

/// Persists the user's chosen trigger modifier across launches.
enum HotkeySettings {

    static let didChangeNotification = Notification.Name("QuickCopyTriggerDidChange")

    private static let triggerDefaultsKey = "QuickCopyTriggerKey"

    static var trigger: TriggerKey {
        get {
            guard let raw = UserDefaults.standard.string(forKey: triggerDefaultsKey),
                  let key = TriggerKey(rawValue: raw) else { return .option }
            return key
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: triggerDefaultsKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
