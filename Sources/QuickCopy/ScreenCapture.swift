import Cocoa
import CoreGraphics

/// Captures a region of the screen so QuickCopy can copy images that are
/// exposed via Accessibility as `AXImage` elements but have no pixel data
/// attribute of their own.
///
/// This requires the separate **Screen Recording** privacy permission (in
/// addition to Accessibility).
enum ScreenCapture {

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system permission prompt if not already granted/denied.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures `rect` (top-left-origin global coordinates, matching AX
    /// frames) from the screen.
    static func capture(rect: CGRect) -> CGImage? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        return CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution, .boundsIgnoreFraming])
    }
}
