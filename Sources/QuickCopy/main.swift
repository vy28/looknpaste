import Cocoa

// QuickCopy is a menu bar (LSUIElement) app. We build the NSApplication
// manually rather than using @main / @NSApplicationMain so the executable
// works both as a raw binary and inside a packaged .app bundle.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// .accessory keeps us out of the Dock and the app switcher even if the
// Info.plist LSUIElement key is missing for some reason.
app.setActivationPolicy(.accessory)

app.run()
