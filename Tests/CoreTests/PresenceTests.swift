import Core
import Settings
import XCTest

final class PresenceTests: XCTestCase {
  func testIdleStartsTheSlideshow() {
    XCTAssertEqual(Presence.desktop.handle(.userIdle).0, .showing(emptyChecks: 0))
    XCTAssertEqual(Presence.desktop.handle(.userIdle).1, [.startSlideshow])
  }

  func testInputEndsTheSlideshowFromEitherState() {
    for state in [Presence.showing(emptyChecks: 1), .displayOff(emptyChecks: 3)] {
      XCTAssertEqual(state.handle(.userActive).0, .desktop)
      XCTAssertEqual(state.handle(.userActive).1, [.stopSlideshow])
    }
  }

  func testOneEmptyCheckKeepsShowing() {
    let (state, effects) = Presence.showing(emptyChecks: 0).handle(.noMotion)
    XCTAssertEqual(state, .showing(emptyChecks: 1))
    XCTAssertEqual(effects, [])
  }

  func testSecondEmptyCheckSleepsTheDisplay() {
    let (state, effects) = Presence.showing(emptyChecks: 1).handle(.noMotion)
    XCTAssertEqual(state, .displayOff(emptyChecks: 0))
    XCTAssertEqual(effects, [.pauseSlideshow, .sleepDisplay])
  }

  func testMotionResetsTheEmptyCount() {
    XCTAssertEqual(Presence.showing(emptyChecks: 1).handle(.motionSeen).0, .showing(emptyChecks: 0))
  }

  func testEmptyChecksWhileOffAreCounted() {
    let (state, effects) = Presence.displayOff(emptyChecks: 2).handle(.noMotion)
    XCTAssertEqual(state, .displayOff(emptyChecks: 3))
    XCTAssertEqual(effects, [])
  }

  func testMotionWakesTheDisplay() {
    let (state, effects) = Presence.displayOff(emptyChecks: 4).handle(.motionSeen)
    XCTAssertEqual(state, .showing(emptyChecks: 0))
    XCTAssertEqual(effects, [.wakeDisplay, .resumeSlideshow])
  }

  func testTurningMotionOffWakesTheDisplay() {
    let (state, effects) = Presence.displayOff(emptyChecks: 0).handle(.motionOff)
    XCTAssertEqual(state, .showing(emptyChecks: 0))
    XCTAssertEqual(effects, [.wakeDisplay, .resumeSlideshow])
    XCTAssertEqual(Presence.showing(emptyChecks: 1).handle(.motionOff).1, [])
  }

  func testIrrelevantEventsChangeNothing() {
    XCTAssertEqual(Presence.desktop.handle(.motionSeen).0, .desktop)
    XCTAssertEqual(Presence.desktop.handle(.userActive).1, [])
    XCTAssertEqual(Presence.showing(emptyChecks: 0).handle(.motionSeen).1, [])
    XCTAssertEqual(Presence.showing(emptyChecks: 0).handle(.showNow).1, [])
  }

  func testOffHoursEndTheSlideshowAndSleepTheDisplay() {
    XCTAssertEqual(
      Presence.showing(emptyChecks: 0).handle(.offHoursBegan).1, [.stopSlideshow, .sleepDisplay])
    let (state, effects) = Presence.displayOff(emptyChecks: 2).handle(.offHoursBegan)
    XCTAssertEqual(state, .desktop)
    XCTAssertEqual(effects, [.stopSlideshow])
    XCTAssertEqual(Presence.desktop.handle(.offHoursBegan).1, [])
  }

  // MARK: Check schedule

  var motion: Settings.Motion {
    var motion = Settings.starter.motion
    motion.enabled = true
    motion.checkEveryMinutes = 5
    motion.quickCheckEverySeconds = 15
    return motion
  }

  func testShowingChecksAtTheLongIntervalAndConfirmsQuickly() {
    XCTAssertEqual(Presence.showing(emptyChecks: 0).secondsUntilMotionCheck(motion), 300)
    XCTAssertEqual(Presence.showing(emptyChecks: 1).secondsUntilMotionCheck(motion), 15)
  }

  func testDisplayOffChecksBackOffToTheLongInterval() {
    let delays = (0..<7).map {
      Presence.displayOff(emptyChecks: $0).secondsUntilMotionCheck(motion)
    }
    XCTAssertEqual(delays, [15, 30, 60, 120, 240, 300, 300])
  }

  func testNoChecksOnTheDesktopOrWithMotionOff() {
    XCTAssertNil(Presence.desktop.secondsUntilMotionCheck(motion))
    var off = motion
    off.enabled = false
    XCTAssertNil(Presence.showing(emptyChecks: 0).secondsUntilMotionCheck(off))
  }
}
