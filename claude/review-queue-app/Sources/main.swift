// main.swift — entry point. Programmatic NSApplication bootstrap (no @main / Scene)
// keeps the build a plain swiftc invocation, matching Claude Launcher's
// script-driven, no-Xcodeproj convention.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar agent, no dock icon
app.run()
