/// Something a key does while the slideshow shows. The raw value is the command's name in the
/// `keys` setting, and every command must have a key there. The command list shows them in the
/// order they're declared here.
public enum Command: String, CaseIterable, CodingKey {
  case next, previous
  /// Stops or restarts the slide timer. Not saved: each slideshow starts playing.
  case pause
  /// Shows or hides the photo info panel.
  case info
  /// Opens the timeframe picker, to choose which photos show by when they were taken.
  case timeframe
  case speed1, speed2, speed3, speed4, speed5
  /// Reads the library folder again for new, changed and removed photos.
  case rescan
  /// Leaves the slideshow for the desktop and opens the settings.
  case settings
  /// Opens the command list, to run any command by name.
  case palette

  /// Shown wherever commands are listed, and on screen when a speed is chosen.
  public var title: String {
    switch self {
    case .next: return "Next Photo"
    case .previous: return "Previous Photo"
    case .pause: return "Pause or Resume"
    case .info: return "Show Photo Info"
    case .timeframe: return "Choose Timeframe…"
    case .speed1, .speed2, .speed3, .speed4, .speed5:
      guard let seconds = slideSeconds else {
        preconditionFailure("every speed command sets slideSeconds")
      }
      return "Speed: \(Self.describe(seconds: seconds))"
    case .rescan: return "Rescan Library"
    case .settings: return "Open Settings…"
    case .palette: return "Show Commands"
    }
  }

  /// The key in `Settings.starter`.
  public var defaultKey: KeySpec {
    switch self {
    case .next: return KeySpec(.named(.right))
    case .previous: return KeySpec(.named(.left))
    case .pause: return KeySpec(.named(.space))
    case .info: return KeySpec(.named(.up))
    case .timeframe: return KeySpec(.character("t"))
    case .speed1: return KeySpec(.character("1"))
    case .speed2: return KeySpec(.character("2"))
    case .speed3: return KeySpec(.character("3"))
    case .speed4: return KeySpec(.character("4"))
    case .speed5: return KeySpec(.character("5"))
    // With ⌘, so a key pressed to end the slideshow doesn't start a scan by accident.
    case .rescan: return KeySpec(.character("r"), modifiers: .cmd)
    // ⌘, opens settings in every Mac app.
    case .settings: return KeySpec(.character(","), modifiers: .cmd)
    case .palette: return KeySpec(.character("k"), modifiers: .cmd)
    }
  }

  /// The `slideSeconds` a speed command sets, or nil for other commands. Fixed, so the keys
  /// mean the same on every Mac; `slideSeconds` itself can be any length.
  public var slideSeconds: Double? {
    switch self {
    case .speed1: return 5
    case .speed2: return 15
    case .speed3: return 30
    case .speed4: return 60
    case .speed5: return 300
    case .next, .previous, .pause, .info, .timeframe, .rescan, .settings, .palette: return nil
    }
  }

  /// Whether holding the key down runs the command again. Stepping through photos does; saving
  /// the same speed over and over doesn't.
  public var repeats: Bool {
    switch self {
    case .next, .previous: return true
    case .pause, .info, .timeframe, .speed1, .speed2, .speed3, .speed4, .speed5, .rescan, .settings,
      .palette:
      return false
    }
  }

  /// Like "15 seconds" or "5 minutes", for a whole number of seconds or minutes.
  public static func describe(seconds: Double) -> String {
    let count = Int(seconds)
    if count < 60 { return count == 1 ? "1 second" : "\(count) seconds" }
    let minutes = count / 60
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}
