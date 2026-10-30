/// Whether the slideshow is showing, and whether the display is on. Pure state machine; the app
/// performs the returned effects.
public enum Presence: Equatable {
  /// Someone is using the Mac. No slideshow.
  case desktop
  case showing
  /// The camera saw no one, so the display is asleep. Motion checks continue.
  case displayOff

  public enum Event: Equatable {
    case userIdle, userActive, showNow, motionSeen, noMotion
    /// Motion mode was switched off in settings.
    case motionOff
  }

  public enum Effect: Equatable {
    case startSlideshow, stopSlideshow, pauseSlideshow, resumeSlideshow, sleepDisplay, wakeDisplay
  }

  public func handle(_ event: Event) -> (Presence, [Effect]) {
    switch (self, event) {
    case (.desktop, .userIdle), (.desktop, .showNow):
      return (.showing, [.startSlideshow])
    case (.showing, .userActive), (.displayOff, .userActive):
      // A key press or mouse move already wakes the display on its own.
      return (.desktop, [.stopSlideshow])
    case (.showing, .noMotion):
      return (.displayOff, [.pauseSlideshow, .sleepDisplay])
    case (.displayOff, .motionSeen), (.displayOff, .motionOff):
      return (.showing, [.wakeDisplay, .resumeSlideshow])
    default:
      return (self, [])
    }
  }
}
