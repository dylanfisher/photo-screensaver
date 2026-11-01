/// A key with modifiers, written in the config file like `"right"`, `"1"` or `"cmd+k"`:
/// modifiers first, joined by `+`, then the key. Case doesn't matter, so `"Cmd+K"` is `"cmd+k"`.
public struct KeySpec: Hashable, Codable, CustomStringConvertible {
  /// Keys that don't type a character, by the name used in the config file.
  public enum Name: String, CaseIterable {
    case left, right, up, down, space, tab, escape, delete
    case `return`
  }

  public enum Key: Hashable {
    case named(Name)
    /// The character the key types with no modifiers held, such as `k`, `1` or `/`.
    case character(Character)
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
      throw SettingsError(description: "\"\(text)\" isn't a key like \"right\", \"1\" or \"cmd+k\"")
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
    } else if last.count == 1, let character = last.first, !character.isWhitespace {
      key = .character(character)
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
