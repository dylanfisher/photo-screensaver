import Settings
import XCTest

final class KeySpecTests: XCTestCase {
  func testParsesNamedAndCharacterKeys() throws {
    XCTAssertEqual(try KeySpec(parsing: "right"), KeySpec(.named(.right)))
    XCTAssertEqual(try KeySpec(parsing: "return"), KeySpec(.named(.return)))
    XCTAssertEqual(try KeySpec(parsing: "1"), KeySpec(.character("1")))
    XCTAssertEqual(try KeySpec(parsing: "/"), KeySpec(.character("/")))
  }

  func testParsesModifiersInAnyOrderAndCase() throws {
    let expected = KeySpec(.character("k"), modifiers: [.cmd, .shift])
    XCTAssertEqual(try KeySpec(parsing: "cmd+shift+k"), expected)
    XCTAssertEqual(try KeySpec(parsing: "Shift+Cmd+K"), expected)
  }

  func testDescriptionIsCanonicalAndParsesBack() throws {
    let spec = try KeySpec(parsing: "cmd+option+ctrl+shift+left")
    XCTAssertEqual(spec.description, "ctrl+option+shift+cmd+left")
    XCTAssertEqual(try KeySpec(parsing: spec.description), spec)
  }

  func testRejectsBadSpecsWithAReason() {
    let cases = [
      ("", "isn't a key"),
      ("cmd+", "isn't a key"),
      ("cmd++k", "isn't a key"),
      ("command+k", "unknown modifier \"command\""),
      ("cmd+cmd+k", "appears twice"),
      ("rght", "unknown key \"rght\""),
      ("cmd+kk", "unknown key \"kk\""),
      (" ", "unknown key"),
    ]
    for (text, reason) in cases {
      XCTAssertThrowsError(try KeySpec(parsing: text), text) { error in
        XCTAssertTrue("\(error)".contains(reason), "\"\(error)\" does not mention \(reason)")
      }
    }
  }
}
