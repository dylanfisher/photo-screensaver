import Settings
import XCTest

final class CommandTests: XCTestCase {
  func testSpeedCommandsSetTheFixedPresets() {
    XCTAssertEqual(
      [Command.speed1, .speed2, .speed3, .speed4, .speed5].map(\.slideSeconds),
      [5, 15, 30, 60, 300])
    XCTAssertNil(Command.next.slideSeconds)
    XCTAssertNil(Command.previous.slideSeconds)
  }

  func testSpeedTitlesSayTheLength() {
    XCTAssertEqual(Command.speed1.title, "Speed: 5 seconds")
    XCTAssertEqual(Command.speed3.title, "Speed: 30 seconds")
    XCTAssertEqual(Command.speed4.title, "Speed: 1 minute")
    XCTAssertEqual(Command.speed5.title, "Speed: 5 minutes")
  }

  func testOnlyStepsRepeat() {
    XCTAssertTrue(Command.next.repeats)
    XCTAssertTrue(Command.previous.repeats)
    XCTAssertFalse(Command.speed2.repeats)
  }

  func testDefaultKeys() {
    XCTAssertEqual(Command.next.defaultKey.description, "right")
    XCTAssertEqual(Command.previous.defaultKey.description, "left")
    XCTAssertEqual(Command.speed3.defaultKey.description, "3")
  }
}
