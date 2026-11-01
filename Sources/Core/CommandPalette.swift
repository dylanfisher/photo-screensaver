import Foundation
import Settings

/// What the command list over the slideshow offers, and how typing narrows it.
public enum CommandPalette {
  /// Every command but the one that opens the list, which would do nothing from inside it, in
  /// the order `Command` declares them.
  public static let commands = Command.allCases.filter { $0 != .palette }

  /// The items whose title contains every word of `query`, ignoring case and accents: first
  /// those where each word starts a word of the title, then the rest, each group in the order
  /// given. An empty query keeps every item.
  public static func filter<Item>(_ items: [Item], by query: String, title: (Item) -> String)
    -> [Item]
  {
    let words = Self.words(query)
    guard !words.isEmpty else { return items }
    var starts: [Item] = []
    var contains: [Item] = []
    for item in items {
      let text = fold(title(item))
      guard words.allSatisfy({ text.contains($0) }) else { continue }
      let titleWords = Self.words(text)
      if words.allSatisfy({ word in titleWords.contains { $0.hasPrefix(word) } }) {
        starts.append(item)
      } else {
        contains.append(item)
      }
    }
    return starts + contains
  }

  private static func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  /// Split on anything but letters and digits, so "Speed: 5" is "speed" and "5".
  private static func words(_ text: String) -> [String] {
    fold(text).components(separatedBy: CharacterSet.alphanumerics.inverted).filter {
      !$0.isEmpty
    }
  }
}
