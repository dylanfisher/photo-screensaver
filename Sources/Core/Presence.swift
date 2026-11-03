import Foundation
import Settings

/// Whether the slideshow is showing, and whether the display is on. Pure state machine; the app
/// performs the returned effects.
public enum Presence: Equatable {
  /// Someone is using the Mac. No slideshow.
  case desktop
  /// `emptyChecks` counts motion checks in a row that saw no one.
  case showing(emptyChecks: Int)
  /// The camera saw no one, so the display is asleep. Motion checks continue; `emptyChecks`
  /// counts those that have seen no one since, and spaces later checks further apart.
  case displayOff(emptyChecks: Int)

  /// Empty checks in a row before the display sleeps. More than one, because sleeping the
  /// display on someone is worse than leaving it on a little longer.
  public static let emptyChecksToSleep = 2

  public enum Event: Equatable {
    case userIdle, userActive, showNow, motionSeen, noMotion
    /// Motion mode was switched off in settings.
    case motionOff
    case offHoursBegan
    /// The slideshow has been up on battery power as long as the settings allow.
    case batteryLimitReached
  }

  public enum Effect: Equatable {
    case startSlideshow, stopSlideshow, pauseSlideshow, resumeSlideshow, sleepDisplay, wakeDisplay
  }

  /// What a key press in the slideshow window does.
  public enum KeyResponse: Equatable {
    case run(Command)
    /// The user is back: send `userActive`.
    case exit
    case ignore
  }

  public func handle(_ event: Event) -> (Presence, [Effect]) {
    switch (self, event) {
    case (.desktop, .userIdle), (.desktop, .showNow):
      // The display can already be asleep: macOS's display sleep may come before the idle time,
      // or the app may start while it's off. Showing means the display is on.
      return (.showing(emptyChecks: 0), [.wakeDisplay, .startSlideshow])
    case (.showing, .userActive), (.displayOff, .userActive):
      // A key press or mouse move already wakes the display on its own.
      return (.desktop, [.stopSlideshow])
    case (.showing, .offHoursBegan), (.showing, .batteryLimitReached):
      return (.desktop, [.stopSlideshow, .sleepDisplay])
    case (.displayOff, .offHoursBegan), (.displayOff, .batteryLimitReached):
      return (.desktop, [.stopSlideshow])
    case (.showing(let empty), .noMotion) where empty + 1 >= Self.emptyChecksToSleep:
      return (.displayOff(emptyChecks: 0), [.pauseSlideshow, .sleepDisplay])
    case (.showing(let empty), .noMotion):
      return (.showing(emptyChecks: empty + 1), [])
    case (.showing, .motionSeen), (.showing, .motionOff):
      return (.showing(emptyChecks: 0), [])
    case (.displayOff(let empty), .noMotion):
      return (.displayOff(emptyChecks: empty + 1), [])
    case (.displayOff, .motionSeen), (.displayOff, .motionOff):
      return (.showing(emptyChecks: 0), [.wakeDisplay, .resumeSlideshow])
    default:
      return (self, [])
    }
  }

  /// Responds to a key press in the slideshow window, given the command bound to it, if any.
  /// While the photos show, a bound key runs its command; an unbound key ends the slideshow, as
  /// does any key while the display is off. Ending waits out the input grace period, like
  /// other input, so a key pressed as the slideshow starts doesn't end it.
  public func respond(toKey bound: Command?, isRepeat: Bool, inGracePeriod: Bool) -> KeyResponse {
    switch (self, bound) {
    case (.desktop, _):
      return .ignore
    case (.showing, .some(let command)):
      return isRepeat && !command.repeats ? .ignore : .run(command)
    case (.showing, .none), (.displayOff, _):
      return inGracePeriod ? .ignore : .exit
    }
  }

  /// Whether key presses count in the input idle check. While the photos show, the slideshow
  /// window handles them instead, but only while it's the key window of the active app: a
  /// window that isn't gets no key presses, and keys must still end the slideshow.
  public func idleCheckCountsKeys(windowGetsKeys: Bool) -> Bool {
    guard case .showing = self else { return true }
    return !windowGetsKeys
  }

  /// Whether mouse and trackpad input counts in the input idle check. Not while the photos
  /// show with the command list open, whose rows are clicked with the pointer; keys still count
  /// whenever the window doesn't get them.
  public func idleCheckCountsPointer(paletteOpen: Bool) -> Bool {
    guard case .showing = self else { return true }
    return !paletteOpen
  }

  /// Whether a sudden light change is worth a motion check now: a light switched on while the
  /// display is off may mean someone came in, and one switched off while the slideshow shows
  /// may mean they left, unless the display is still within `stayOnMinutes`.
  /// `displayOnFor` is seconds since the display came on, and is ignored while it's off.
  public func checksNow(
    after change: LightWatch.Change, motion: Settings.Motion, displayOnFor: Double
  ) -> Bool {
    switch (self, change) {
    case (.displayOff, .brighter):
      return true
    case (.showing, .darker):
      return displayOnFor >= motion.stayOnMinutes * 60
    default:
      return false
    }
  }

  /// Seconds until the next motion check, or nil when none should run. While showing, none run
  /// until the display has been on for `stayOnMinutes`, so nothing can turn it off sooner. After
  /// that, checks are `checkEveryMinutes` apart, but an empty check is confirmed after
  /// `quickCheckEverySeconds`. While the display is off, checks start `quickCheckEverySeconds`
  /// apart, since someone who just stepped away often comes back soon, and the gap doubles
  /// after each empty check up to `checkEveryMinutes`.
  public func secondsUntilMotionCheck(_ motion: Settings.Motion, displayOnFor: Double) -> Double? {
    guard motion.enabled else { return nil }
    let longest = motion.checkEveryMinutes * 60
    switch self {
    case .desktop:
      return nil
    case .showing(let empty):
      guard empty == 0 else { return motion.quickCheckEverySeconds }
      return max(longest, motion.stayOnMinutes * 60 - displayOnFor)
    case .displayOff(let empty):
      return min(motion.quickCheckEverySeconds * pow(2, Double(empty)), longest)
    }
  }
}
