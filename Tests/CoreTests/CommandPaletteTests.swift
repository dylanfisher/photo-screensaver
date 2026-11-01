import Core
import Settings
import XCTest

final class CommandPaletteTests: XCTestCase {
  func testListsEveryCommandButItsOwnInDeclaredOrder() {
    XCTAssertEqual(CommandPalette.commands, Command.allCases.filter { $0 != .palette })
    XCTAssertEqual(CommandPalette.commands.first, .next)
  }

  func testAnEmptyQueryKeepsEverything() {
    XCTAssertEqual(filter(""), CommandPalette.commands)
    XCTAssertEqual(filter("  "), CommandPalette.commands)
  }

  func testMatchesIgnoringCaseAndAccents() {
    XCTAssertEqual(filter("RESCAN"), [.rescan])
    XCTAssertEqual(filter("réscan"), [.rescan])
  }

  func testWordStartsComeBeforeMatchesInsideWords() {
    // "re" starts "Resume" and "Rescan", and is inside "Previous".
    XCTAssertEqual(filter("re"), [.pause, .rescan, .previous])
  }

  func testEveryWordMustMatch() {
    // "15 seconds" has a 5 inside a word, so it comes after "5 seconds" and "5 minutes".
    XCTAssertEqual(filter("speed 5"), [.speed1, .speed5, .speed2])
    XCTAssertEqual(filter("photo next"), [.next])
    XCTAssertEqual(filter("next banana"), [])
  }

  func testFiltersAnyItemsByTheirTitle() {
    XCTAssertEqual(
      CommandPalette.filter(["All time", "2014", "2015"], by: "201") { $0 }, ["2014", "2015"])
  }

  private func filter(_ query: String) -> [Command] {
    CommandPalette.filter(CommandPalette.commands, by: query) { $0.title }
  }
}
