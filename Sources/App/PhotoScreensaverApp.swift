import AppKit

/// Menu-bar only: no Dock icon (LSUIElement in Support/Info.plist).
@main
enum PhotoScreensaverApp {
  @MainActor
  static func main() {
    // NSApplication first: AppController's menu-bar item needs the window server connection.
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.run()
  }
}
