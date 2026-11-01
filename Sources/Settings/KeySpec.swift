/// A key with modifiers, written in the config file like `"right"`, `"1"` or `"cmd+k"`:
/// modifiers first, joined by `+`, then the key. Case doesn't matter, so `"Cmd+K"` is `"cmd+k"`.
///
/// A character names a key by where it is on a US keyboard, whatever layout the Mac uses: `"1"`
/// is the key left of 2 even on a French layout, where it types `&`, and `"q"` is the key left
/// of W. So every key can be named with characters a US keyboard types without Shift.
public struct KeySpec: Hashable, Codable, CustomStringConvertible {
  /// Keys that don't type a character, by the name used in the config file.
  public enum Name: String, CaseIterable {
    case left, right, up, down, space, tab, escape, delete
    case `return`
    /// The keypad's +, since `+` joins modifiers. The + over = is `shift+=`.
    case plus
    /// The ⌦ key, on extended keyboards and as fn+delete.
    case forwardDelete = "forwarddelete"
  }

  public enum Key: Hashable {
    case named(Name)
    /// The character the key types on a US keyboard with no modifiers held, such as `k`, `1`
    /// or `/`.
    case character(Character)

    /// The key with virtual key code `keyCode`, or nil for one that has no name here. Key codes,
    /// from Carbon's `Events.h`, number positions on the keyboard, not what they type. Keypad
    /// digits are the same keys as the digits above the letters.
    public init?(keyCode: UInt16) {
      guard let key = Self.keyCodes[keyCode] else { return nil }
      self = key
    }

    static let keyCodes: [UInt16: Key] = {
      var keys: [UInt16: Key] = [
        123: .named(.left), 124: .named(.right), 125: .named(.down), 126: .named(.up),
        49: .named(.space), 48: .named(.tab), 53: .named(.escape), 51: .named(.delete),
        36: .named(.return), 76: .named(.return), 69: .named(.plus), 117: .named(.forwardDelete),
      ]
      // The US ANSI layout, as `kVK_ANSI_*` in `Events.h`.
      let characters: [(UInt16, Character)] = [
        (0, "a"), (1, "s"), (2, "d"), (3, "f"), (4, "h"), (5, "g"), (6, "z"), (7, "x"),
        (8, "c"), (9, "v"), (11, "b"), (12, "q"), (13, "w"), (14, "e"), (15, "r"), (16, "y"),
        (17, "t"), (18, "1"), (19, "2"), (20, "3"), (21, "4"), (22, "6"), (23, "5"), (24, "="),
        (25, "9"), (26, "7"), (27, "-"), (28, "8"), (29, "0"), (30, "]"), (31, "o"), (32, "u"),
        (33, "["), (34, "i"), (35, "p"), (37, "l"), (38, "j"), (39, "'"), (40, "k"), (41, ";"),
        (42, "\\"), (43, ","), (44, "/"), (45, "n"), (46, "m"), (47, "."), (50, "`"),
        // The keypad.
        (65, "."), (67, "*"), (75, "/"), (78, "-"), (81, "="), (82, "0"), (83, "1"), (84, "2"),
        (85, "3"), (86, "4"), (87, "5"), (88, "6"), (89, "7"), (91, "8"), (92, "9"),
      ]
      for (code, character) in characters { keys[code] = .character(character) }
      return keys
    }()

    /// Every character that names a key.
    static let characters = Set(
      keyCodes.values.compactMap { key -> Character? in
        guard case .character(let character) = key else { return nil }
        return character
      })
  }

  public struct Modifiers: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let ctrl = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let cmd = Modifiers(rawValue: 1 << 3)

    /// In the order they're written, which is the order macOS menus show them.
    static let names: [(String, Modifiers)] = [
      ("ctrl", .ctrl), ("option", .option), ("shift", .shift), ("cmd", .cmd),
    ]
  }

  public var key: Key
  public var modifiers: Modifiers

  public init(_ key: Key, modifiers: Modifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }

  public init(parsing text: String) throws {
    let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
    guard let last = parts.last, !last.isEmpty, parts.dropLast().allSatisfy({ !$0.isEmpty })
    else {
      throw SettingsError(
        description:
          "\"\(text)\" isn't a key like \"right\", \"1\" or \"cmd+k\"; the keypad's + is \"plus\"")
    }
    var modifiers: Modifiers = []
    for part in parts.dropLast() {
      guard let modifier = Modifiers.names.first(where: { $0.0 == part })?.1 else {
        let known = Modifiers.names.map(\.0).joined(separator: ", ")
        throw SettingsError(
          description: "unknown modifier \"\(part)\" in \"\(text)\"; use \(known)")
      }
      if modifiers.contains(modifier) {
        throw SettingsError(description: "\"\(part)\" appears twice in \"\(text)\"")
      }
      modifiers.insert(modifier)
    }
    let key: Key
    if let name = Name(rawValue: String(last)) {
      key = .named(name)
    } else if last.count == 1, let character = last.first, Key.characters.contains(character) {
      key = .character(character)
    } else if last.count == 1 {
      throw SettingsError(
        description: "unknown key \"\(last)\" in \"\(text)\"; a character names the key that "
          + "types it on a US keyboard without Shift, so ! is \"shift+1\"")
    } else {
      let names = Name.allCases.map(\.rawValue).joined(separator: ", ")
      throw SettingsError(
        description: "unknown key \"\(last)\" in \"\(text)\"; use one character or \(names)")
    }
    self.init(key, modifiers: modifiers)
  }

  public var description: String {
    let modifierNames = Modifiers.names.filter { modifiers.contains($0.1) }.map(\.0)
    let keyName: String
    switch key {
    case .named(let name): keyName = name.rawValue
    case .character(let character): keyName = String(character)
    }
    return (modifierNames + [keyName]).joined(separator: "+")
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    do {
      try self.init(parsing: container.decode(String.self))
    } catch let error as SettingsError {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }
}
