import AppKit

let bundleID = "io.github.xinding33.ripple"
/// Builds before 1.1 used this bundle ID, preferences domain and login agent label.
let legacyBundleID = "com.xinding.Ripple"

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
