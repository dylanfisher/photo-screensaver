import AppKit
import Core
import Settings
import SwiftUI

/// The settings window: `SettingsView` in an ordinary titled window. The app is menu-bar only,
/// so showing the window activates the app, and closing it gives the keys back to the app that
/// had them (docs/decisions/0009-settings-window.md).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  private let model: SettingsModel
  private let actions: SettingsView.Actions
  /// Built when the window is shown and let go when it closes, with its form.
  private var window: SettingsWindow?
  /// The app that had the keys when the window opened, which gets them back when it closes.
  private var previousApp: NSRunningApplication?

  init(model: SettingsModel, actions: SettingsView.Actions) {
    self.model = model
    self.actions = actions
  }

  /// Brings the window forward, making it if it isn't open.
  func show() {
    model.reload()
    let window = self.window ?? makeWindow()
    if !NSApp.isActive {
      let frontmost = NSWorkspace.shared.frontmostApplication
      previousApp = frontmost == .current ? nil : frontmost
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// Shows an edit to the config file, while the window is open.
  func fileChanged() {
    guard window != nil else { return }
    model.reload()
  }

  private func makeWindow() -> SettingsWindow {
    // macOS 12's hosting controller sizes the window to the view's ideal size.
    let hosting = NSHostingController(rootView: SettingsView(model: model, actions: actions))
    let window = SettingsWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable, .resizable]
    window.title = "Photo Screensaver Settings"
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.onRecordingKey = { [model] event in model.record(KeySpec(event)) }
    window.center()
    self.window = window
    return window
  }

  func windowWillClose(_ notification: Notification) {
    model.stopRecording()
    window = nil
    let frontmost = NSWorkspace.shared.frontmostApplication
    // The user may have switched apps with the window open; closing it mustn't pull them back.
    if frontmost == nil || frontmost == .current {
      if let previousApp, !previousApp.isTerminated {
        previousApp.activate(options: .activateIgnoringOtherApps)
      } else {
        // A menu-bar app with no window would keep the keys, with nothing to type into.
        NSApp.hide(nil)
      }
    }
    previousApp = nil
  }

  /// A key half recorded when the user clicks into another window or app is dropped.
  func windowDidResignKey(_ notification: Notification) {
    model.stopRecording()
  }
}

/// Takes the keys a menu bar would: ⌘W, ⌘Q and the text editing ones, since this app has none.
/// While a command's key is being recorded, every key press goes to the recorder first.
@MainActor
final class SettingsWindow: NSWindow {
  /// Given each key press while recording; returns whether it took it.
  var onRecordingKey: (NSEvent) -> Bool = { _ in false }

  /// Every key press reaches the window here before the first responder, which as a text field
  /// or a button would take Tab, Space or Return.
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, onRecordingKey(event) { return }
    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
    if onRecordingKey(event) { return true }
    // By the key's position, like the slideshow's keys, so a layout without Latin letters works.
    guard let spec = KeySpec(event), spec.modifiers == .cmd,
      case .character(let character) = spec.key
    else { return super.performKeyEquivalent(with: event) }
    let edits: [Character: Selector] = [
      "a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
      "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
    ]
    switch character {
    case "w": performClose(nil)
    case "q": NSApp.terminate(nil)
    default:
      guard let action = edits[character] else { return super.performKeyEquivalent(with: event) }
      NSApp.sendAction(action, to: nil, from: self)
    }
    return true
  }
}
