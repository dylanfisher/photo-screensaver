import AppKit
import Settings

extension NSEvent {
  /// The letter of a ⌘ shortcut such as ⌘C or ⌘W, or nil if the key press isn't one with ⌘
  /// alone. Standard shortcuts follow the layout, as macOS menus do, so ⌘C on Dvorak is the key
  /// that types C there. A layout that types no Latin letter falls back to the key's position on
  /// a US keyboard, as macOS does for menu shortcuts.
  var commandLetter: Character? {
    let held = modifierFlags.intersection([.command, .control, .option, .shift])
    guard type == .keyDown, held == .command else { return nil }
    if let typed = charactersIgnoringModifiers?.lowercased(), typed.count == 1,
      let character = typed.first, character.isASCII, character.isLetter
    {
      return character
    }
    guard let spec = KeySpec(self), case .character(let character) = spec.key else { return nil }
    return character
  }

  /// The text editing action of ⌘A, ⌘C, ⌘V or ⌘X, which a menu bar's Edit menu would send.
  /// This app has no menu bar, so windows with text fields send it themselves.
  var editAction: Selector? {
    switch commandLetter {
    case "a": return #selector(NSText.selectAll(_:))
    case "c": return #selector(NSText.copy(_:))
    case "v": return #selector(NSText.paste(_:))
    case "x": return #selector(NSText.cut(_:))
    default: return nil
    }
  }
}
