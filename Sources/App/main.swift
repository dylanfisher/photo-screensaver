import AppKit

// Menu-bar only: no Dock icon (LSUIElement in the bundle's Info.plist).
let app = NSApplication.shared
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "📷"
let menu = NSMenu()
menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
statusItem.menu = menu
app.run()
