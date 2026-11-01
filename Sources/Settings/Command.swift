/// Something a key does while the slideshow shows. The raw value is the command's name in the
/// `keys` setting, and every command must have a key there.
public enum Command: String, CaseIterable, CodingKey {
  case next, previous
  case speed1, speed2, speed3, speed4, speed5

  /// Shown wherever commands are listed, and on screen when a speed is chosen.
  public var title: String {
    switch self {
    case .next: return "Next Photo"
    case .previous: return "Previous Photo"
    case .speed1, .speed2, .speed3, .speed4, .speed5:
      guard let seconds = slideSeconds else {
        preconditionFailure("every speed command sets slideSeconds")
      }
      return "Speed: \(Self.describe(seconds: seconds))"
    }
  }

  /// The key in `Settings.starter`.
  public var defaultKey: KeySpec {
    switch self {
    case .next: return KeySpec(.named(.right))
    case .previous: return KeySpec(.named(.left))
    case .speed1: return KeySpec(.character("1"))
    case .speed2: return KeySpec(.character("2"))
    case .speed3: return KeySpec(.character("3"))
    case .speed4: return KeySpec(.character("4"))
    case .speed5: return KeySpec(.character("5"))
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
    case .next, .previous: return nil
    }
  }

  /// Whether holding the key down runs the command again. Stepping through photos does; saving
  /// the same speed over and over doesn't.
  public var repeats: Bool {
    switch self {
    case .next, .previous: return true
    case .speed1, .speed2, .speed3, .speed4, .speed5: return false
    }
  }

  private static func describe(seconds: Double) -> String {
    let count = Int(seconds)
    if count < 60 { return count == 1 ? "1 second" : "\(count) seconds" }
    let minutes = count / 60
    return minutes == 1 ? "1 minute" : "\(minutes) minutes"
  }
}
