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
      ("!", "shift+1"),
      ("é", "US keyboard"),
    ]
    for (text, reason) in cases {
      XCTAssertThrowsError(try KeySpec(parsing: text), text) { error in
        XCTAssertTrue("\(error)".contains(reason), "\"\(error)\" does not mention \(reason)")
      }
    }
  }

  func testKeyCodesNameKeysByTheirPlaceOnAUSKeyboard() {
    XCTAssertEqual(KeySpec.Key(keyCode: 18), .character("1"))
    XCTAssertEqual(KeySpec.Key(keyCode: 23), .character("5"))
    XCTAssertEqual(KeySpec.Key(keyCode: 12), .character("q"))
    XCTAssertEqual(KeySpec.Key(keyCode: 44), .character("/"))
    XCTAssertEqual(KeySpec.Key(keyCode: 42), .character("\\"))
    XCTAssertEqual(KeySpec.Key(keyCode: 124), .named(.right))
    XCTAssertNil(KeySpec.Key(keyCode: 122), "F1 has no name")
  }

  func testKeypadDigitsAreTheDigitKeys() {
    XCTAssertEqual(KeySpec.Key(keyCode: 83), .character("1"))
    XCTAssertEqual(KeySpec.Key(keyCode: 82), .character("0"))
    XCTAssertEqual(KeySpec.Key(keyCode: 92), .character("9"))
    XCTAssertEqual(KeySpec.Key(keyCode: 76), .named(.return))
    XCTAssertEqual(KeySpec.Key(keyCode: 69), .named(.plus))
  }

  func testPlusAndForwardDeleteAreNamedKeys() throws {
    XCTAssertEqual(try KeySpec(parsing: "cmd+plus"), KeySpec(.named(.plus), modifiers: .cmd))
    XCTAssertEqual(KeySpec(.named(.plus), modifiers: .cmd).description, "cmd+plus")
    XCTAssertEqual(try KeySpec(parsing: "ForwardDelete"), KeySpec(.named(.forwardDelete)))
    XCTAssertEqual(KeySpec(.named(.forwardDelete)).description, "forwarddelete")
    XCTAssertEqual(KeySpec.Key(keyCode: 117), .named(.forwardDelete))
    XCTAssertThrowsError(try KeySpec(parsing: "cmd++")) { error in
      XCTAssertTrue("\(error)".contains("\"plus\""), "\(error)")
    }
  }

  func testEveryCharacterKeyParsesBack() throws {
    for code in UInt16(0)...127 {
      guard let key = KeySpec.Key(keyCode: code) else { continue }
      let spec = KeySpec(key)
      XCTAssertEqual(try KeySpec(parsing: spec.description), spec, "key code \(code)")
    }
  }

  func testEveryDefaultKeyHasAKeyCode() {
    let reachable = Set((UInt16(0)...127).compactMap { KeySpec.Key(keyCode: $0) })
    for command in Command.allCases {
      XCTAssertTrue(reachable.contains(command.defaultKey.key), command.rawValue)
    }
  }
}
