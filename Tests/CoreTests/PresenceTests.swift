import Core
import XCTest

final class PresenceTests: XCTestCase {
  func testIdleStartsTheSlideshow() {
    XCTAssertEqual(Presence.desktop.handle(.userIdle).0, .showing)
    XCTAssertEqual(Presence.desktop.handle(.userIdle).1, [.startSlideshow])
  }

  func testInputEndsTheSlideshowFromEitherState() {
    for state in [Presence.showing, .displayOff] {
      XCTAssertEqual(state.handle(.userActive).0, .desktop)
      XCTAssertEqual(state.handle(.userActive).1, [.stopSlideshow])
    }
  }

  func testNoMotionSleepsTheDisplay() {
    let (state, effects) = Presence.showing.handle(.noMotion)
    XCTAssertEqual(state, .displayOff)
    XCTAssertEqual(effects, [.pauseSlideshow, .sleepDisplay])
  }

  func testMotionWakesTheDisplay() {
    let (state, effects) = Presence.displayOff.handle(.motionSeen)
    XCTAssertEqual(state, .showing)
    XCTAssertEqual(effects, [.wakeDisplay, .resumeSlideshow])
  }

  func testTurningMotionOffWakesTheDisplay() {
    let (state, effects) = Presence.displayOff.handle(.motionOff)
    XCTAssertEqual(state, .showing)
    XCTAssertEqual(effects, [.wakeDisplay, .resumeSlideshow])
    XCTAssertEqual(Presence.showing.handle(.motionOff).1, [])
  }

  func testIrrelevantEventsChangeNothing() {
    XCTAssertEqual(Presence.desktop.handle(.motionSeen).0, .desktop)
    XCTAssertEqual(Presence.desktop.handle(.userActive).1, [])
    XCTAssertEqual(Presence.showing.handle(.motionSeen).1, [])
    XCTAssertEqual(Presence.showing.handle(.showNow).1, [])
    XCTAssertEqual(Presence.displayOff.handle(.noMotion).1, [])
  }
}
