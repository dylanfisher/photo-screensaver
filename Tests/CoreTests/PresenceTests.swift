import Core
import Settings
import XCTest

final class PresenceTests: XCTestCase {
  func testIdleStartsTheSlideshowWithTheDisplayOn() {
    XCTAssertEqual(Presence.desktop.handle(.userIdle).0, .showing(emptyChecks: 0))
    XCTAssertEqual(Presence.desktop.handle(.userIdle).1, [.wakeDisplay, .startSlideshow])
    XCTAssertEqual(Presence.desktop.handle(.showNow).1, [.wakeDisplay, .startSlideshow])
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

  func testBatteryLimitEndsTheSlideshowAndSleepsTheDisplay() {
    XCTAssertEqual(
      Presence.showing(emptyChecks: 0).handle(.batteryLimitReached).1,
      [.stopSlideshow, .sleepDisplay])
    let (state, effects) = Presence.displayOff(emptyChecks: 2).handle(.batteryLimitReached)
    XCTAssertEqual(state, .desktop)
    XCTAssertEqual(effects, [.stopSlideshow])
    XCTAssertEqual(Presence.desktop.handle(.batteryLimitReached).1, [])
  }

  func testLightChangesThatCallForACheckNow() {
    let on = 30 * 60.0
    XCTAssertTrue(
      Presence.displayOff(emptyChecks: 3).checksNow(
        after: .brighter, motion: motion, displayOnFor: 0))
    XCTAssertTrue(
      Presence.showing(emptyChecks: 0).checksNow(after: .darker, motion: motion, displayOnFor: on))
    XCTAssertFalse(
      Presence.displayOff(emptyChecks: 3).checksNow(after: .darker, motion: motion, displayOnFor: 0)
    )
    XCTAssertFalse(
      Presence.showing(emptyChecks: 0).checksNow(after: .brighter, motion: motion, displayOnFor: on)
    )
    XCTAssertFalse(Presence.desktop.checksNow(after: .brighter, motion: motion, displayOnFor: on))
  }

  func testLightOffDoesNotCheckWhileTheDisplayMustStayOn() {
    XCTAssertFalse(
      Presence.showing(emptyChecks: 0).checksNow(after: .darker, motion: motion, displayOnFor: 600))
  }

  // MARK: Keys

  func testBoundKeysRunTheirCommandWhileShowing() {
    let showing = Presence.showing(emptyChecks: 1)
    XCTAssertEqual(
      showing.respond(toKey: .next, isRepeat: false, inGracePeriod: false), .run(.next))
    XCTAssertEqual(
      showing.respond(toKey: .previous, isRepeat: true, inGracePeriod: false), .run(.previous))
    XCTAssertEqual(
      showing.respond(toKey: .speed2, isRepeat: false, inGracePeriod: true), .run(.speed2))
    XCTAssertEqual(showing.respond(toKey: .speed2, isRepeat: true, inGracePeriod: false), .ignore)
  }

  func testUnboundKeysEndTheSlideshowAfterTheGracePeriod() {
    let showing = Presence.showing(emptyChecks: 0)
    XCTAssertEqual(showing.respond(toKey: nil, isRepeat: false, inGracePeriod: false), .exit)
    XCTAssertEqual(showing.respond(toKey: nil, isRepeat: false, inGracePeriod: true), .ignore)
  }

  func testAnyKeyWakesFromDisplayOff() {
    let off = Presence.displayOff(emptyChecks: 2)
    XCTAssertEqual(off.respond(toKey: .next, isRepeat: false, inGracePeriod: false), .exit)
    XCTAssertEqual(off.respond(toKey: nil, isRepeat: false, inGracePeriod: false), .exit)
    XCTAssertEqual(
      Presence.desktop.respond(toKey: nil, isRepeat: false, inGracePeriod: false), .ignore)
  }

  func testIdleCheckLeavesKeysToTheWindowOnlyWhileShowing() {
    XCTAssertFalse(Presence.showing(emptyChecks: 0).idleCheckCountsKeys(windowGetsKeys: true))
    XCTAssertTrue(Presence.showing(emptyChecks: 0).idleCheckCountsKeys(windowGetsKeys: false))
    XCTAssertTrue(Presence.displayOff(emptyChecks: 0).idleCheckCountsKeys(windowGetsKeys: true))
    XCTAssertTrue(Presence.desktop.idleCheckCountsKeys(windowGetsKeys: false))
  }

  func testIdleCheckLeavesThePointerToAnOpenPalette() {
    XCTAssertFalse(Presence.showing(emptyChecks: 0).idleCheckCountsPointer(paletteOpen: true))
    XCTAssertTrue(Presence.showing(emptyChecks: 0).idleCheckCountsPointer(paletteOpen: false))
    XCTAssertTrue(Presence.displayOff(emptyChecks: 0).idleCheckCountsPointer(paletteOpen: true))
    XCTAssertTrue(Presence.desktop.idleCheckCountsPointer(paletteOpen: true))
  }

  // MARK: Check schedule

  var motion: Settings.Motion {
    var motion = Settings.starter.motion
    motion.enabled = true
    motion.stayOnMinutes = 30
    motion.checkEveryMinutes = 5
    motion.quickCheckEverySeconds = 15
    return motion
  }

  func testNoChecksUntilTheDisplayHasStayedOn() {
    XCTAssertEqual(
      Presence.showing(emptyChecks: 0).secondsUntilMotionCheck(motion, displayOnFor: 0), 1800)
    XCTAssertEqual(
      Presence.showing(emptyChecks: 0).secondsUntilMotionCheck(motion, displayOnFor: 1000), 800)
  }

  func testShowingChecksAtTheLongIntervalAndConfirmsQuickly() {
    let on = 40 * 60.0
    XCTAssertEqual(
      Presence.showing(emptyChecks: 0).secondsUntilMotionCheck(motion, displayOnFor: on), 300)
    XCTAssertEqual(
      Presence.showing(emptyChecks: 1).secondsUntilMotionCheck(motion, displayOnFor: on), 15)
  }

  func testDisplayOffChecksBackOffToTheLongInterval() {
    let delays = (0..<7).map {
      Presence.displayOff(emptyChecks: $0).secondsUntilMotionCheck(motion, displayOnFor: 0)
    }
    XCTAssertEqual(delays, [15, 30, 60, 120, 240, 300, 300])
  }

  func testNoChecksOnTheDesktopOrWithMotionOff() {
    XCTAssertNil(Presence.desktop.secondsUntilMotionCheck(motion, displayOnFor: 0))
    var off = motion
    off.enabled = false
    XCTAssertNil(Presence.showing(emptyChecks: 0).secondsUntilMotionCheck(off, displayOnFor: 0))
  }
}
