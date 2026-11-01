import AppKit
import Settings

extension KeySpec {
  /// The spec a key press matches, or nil for a key that has no name. Keys are matched by their
  /// position, so a spec means the same key on any keyboard layout, and `shift+1` is the 1 key
  /// with Shift held, not `!`.
  init?(_ event: NSEvent) {
    guard let key = Key(keyCode: event.keyCode) else { return nil }
    var modifiers: Modifiers = []
    let flags = event.modifierFlags
    if flags.contains(.control) { modifiers.insert(.ctrl) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.command) { modifiers.insert(.cmd) }
    self.init(key, modifiers: modifiers)
  }
}
