import AppKit
import Core
import Settings
import SwiftUI

/// The settings window: a toolbar of panes, each a `SettingsView`, in an ordinary titled window.
/// The app is menu-bar only, so showing the window activates the app, and closing it gives the
/// keys back to the app that had them (docs/decisions/0009-settings-window.md,
/// docs/decisions/0012-settings-panes.md).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
  private let model: SettingsModel
  private let actions: SettingsView.Actions
  /// Built when the window is shown and let go when it closes, with its form.
  private var window: SettingsWindow?
  private var hosting: NSHostingController<SettingsView>?
  /// The pane showing, or shown last; the window opens at it again.
  private var pane = SettingsView.Pane.general
  /// What's typed in the window's fields and not yet saved.
  private var edits: PendingEdits?
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

  /// Whether the window is on screen, where a slideshow starting on its own would cover it.
  var isVisible: Bool { window?.isVisible == true && !NSApp.isHidden }

  /// Saves what's typed in the fields and not yet saved, as before the app quits.
  func saveEdits() {
    edits?.save()
  }

  /// Shows an edit to the config file, while the window is open.
  func fileChanged() {
    guard window != nil else { return }
    model.reload()
  }

  private func makeWindow() -> SettingsWindow {
    // macOS 12's hosting controller sizes the window to the view's ideal size.
    let edits = PendingEdits()
    let hosting = NSHostingController(rootView: view(of: pane, edits: edits))
    let window = SettingsWindow(contentViewController: hosting)
    window.styleMask = [.titled, .closable]
    window.title = pane.title
    let toolbar = NSToolbar(identifier: "SettingsToolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconAndLabel
    window.toolbar = toolbar
    window.toolbarStyle = .preference
    toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(pane.rawValue)
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.onRecordingKey = { [model] event in model.record(KeySpec(event)) }
    window.center()
    self.window = window
    self.hosting = hosting
    self.edits = edits
    return window
  }

  private func view(of pane: SettingsView.Pane, edits: PendingEdits) -> SettingsView {
    SettingsView(model: model, actions: actions, edits: edits, pane: pane)
  }

  /// Shows `pane`, keeping the window's top edge where it is as its height changes.
  private func select(_ pane: SettingsView.Pane) {
    guard let window, let hosting, let edits, pane != self.pane else { return }
    // The pane's fields go away without losing focus first.
    edits.save()
    model.stopRecording()
    self.pane = pane
    hosting.rootView = view(of: pane, edits: edits)
    window.title = pane.title
    let size = hosting.view.fittingSize
    var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
    frame.origin = NSPoint(
      x: window.frame.minX, y: window.frame.maxY - frame.height)
    window.setFrame(frame, display: true, animate: true)
  }

  @objc private func selected(_ item: NSToolbarItem) {
    guard let pane = SettingsView.Pane(rawValue: item.itemIdentifier.rawValue) else { return }
    select(pane)
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    SettingsView.Pane.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbar(
    _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar flag: Bool
  ) -> NSToolbarItem? {
    guard let pane = SettingsView.Pane(rawValue: identifier.rawValue) else { return nil }
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = pane.title
    item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
    item.target = self
    item.action = #selector(selected(_:))
    return item
  }

  func windowWillClose(_ notification: Notification) {
    model.stopRecording()
    // The fields save as they lose focus, which SwiftUI reports after the window is gone.
    edits?.save()
    edits = nil
    hosting = nil
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
  /// The key code of a key the recorder took and that is still held. Its repeats and its
  /// release are dropped, or they'd reach the button just recorded, and Space or Return would
  /// press it and start recording again.
  private var heldKeyCode: UInt16?

  /// Every key press reaches the window here before the first responder, which as a text field
  /// or a button would take Tab, Space or Return.
  override func sendEvent(_ event: NSEvent) {
    if handledAsRecorded(event) { return }
    super.sendEvent(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
    if handledAsRecorded(event) { return true }
    switch event.commandLetter {
    case "w": performClose(nil)
    case "q": NSApp.terminate(nil)
    default:
      guard let action = event.editAction else { return super.performKeyEquivalent(with: event) }
      NSApp.sendAction(action, to: nil, from: self)
    }
    return true
  }

  /// Gives a key press to the recorder, or drops the repeats and release of one it took, and
  /// returns whether the event is used up.
  private func handledAsRecorded(_ event: NSEvent) -> Bool {
    switch event.type {
    case .keyDown:
      if event.isARepeat, event.keyCode == heldKeyCode { return true }
      guard onRecordingKey(event) else { return false }
      heldKeyCode = event.keyCode
      return true
    case .keyUp:
      guard event.keyCode == heldKeyCode else { return false }
      heldKeyCode = nil
      return true
    default:
      return false
    }
  }
}
