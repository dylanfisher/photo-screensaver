import AppKit
import Settings

extension KeySpec {
  /// The spec a key press matches, or nil for a key that has no name and types no character.
  /// Named keys are matched by key code, so they work on any keyboard layout; other keys by the
  /// character they type with no modifiers, so `shift+1` is the 1 key with Shift held, not `!`.
  init?(_ event: NSEvent) {
    var modifiers: Modifiers = []
    let flags = event.modifierFlags
    if flags.contains(.control) { modifiers.insert(.ctrl) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.command) { modifiers.insert(.cmd) }

    if let name = Self.names[event.keyCode] {
      self.init(.named(name), modifiers: modifiers)
    } else if let characters = event.characters(byApplyingModifiers: []),
      characters.count == 1, let character = characters.lowercased().first,
      !character.isWhitespace, !character.isNewline
    {
      self.init(.character(character), modifiers: modifiers)
    } else {
      return nil
    }
  }

  private static let names = Dictionary(
    uniqueKeysWithValues: Name.allCases.map { (keyCode(of: $0), $0) })

  /// Virtual key codes from Carbon's `Events.h`, which name physical keys.
  private static func keyCode(of name: Name) -> UInt16 {
    switch name {
    case .left: return 123
    case .right: return 124
    case .down: return 125
    case .up: return 126
    case .space: return 49
    case .tab: return 48
    case .escape: return 53
    case .delete: return 51
    case .return: return 36
    }
  }
}
