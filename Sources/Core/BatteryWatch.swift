import Settings

/// Applies `Settings.Battery`: how long the slideshow may stay up on battery power, and whether
/// it may start (docs/decisions/0010-battery-limit.md).
public struct BatteryWatch: Equatable {
  /// Uptime since when the slideshow has been up on battery power, or nil when it isn't.
  private var since: Double?
  /// Whether the slideshow stopped at the limit and no one has used the Mac since. Without it,
  /// the input idle time, still past `idleMinutes`, would start it again at once.
  private var stopped = false

  public init() {}

  /// Called each tick with whether the slideshow is up, display off included. Returns whether
  /// it must stop now. Time on power doesn't count, and unplugging starts the count afresh.
  public mutating func update(
    onBattery: Bool, showing: Bool, at now: Double, battery: Settings.Battery
  ) -> Bool {
    guard onBattery, showing, battery.mode != .always else {
      since = nil
      return false
    }
    let start = since ?? now
    since = start
    let limit = battery.mode == .never ? 0 : battery.limitMinutes * 60
    guard now - start >= limit else { return false }
    since = nil
    stopped = true
    return true
  }

  /// Someone has used the Mac since the slideshow stopped.
  public mutating func userReturned() {
    stopped = false
  }

  /// Whether the slideshow may start once the Mac is idle.
  public func startsOnItsOwn(onBattery: Bool, battery: Settings.Battery) -> Bool {
    guard onBattery else { return true }
    switch battery.mode {
    case .always: return true
    case .limited: return !stopped
    case .never: return false
    }
  }

  /// Whether Show Slideshow may start it. A hand start on battery gets a whole limit.
  public static func startsByHand(onBattery: Bool, battery: Settings.Battery) -> Bool {
    !onBattery || battery.mode != .never
  }
}
