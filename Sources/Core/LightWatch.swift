/// Spots sudden changes in room light, such as a lamp switched on or off, among regular light
/// sensor readings. Slow drift, like daylight fading, doesn't count.
public struct LightWatch {
  /// A change counts when the level moves by at least this factor within `windowSeconds`.
  static let factor = 1.5
  static let windowSeconds = 5.0
  /// Added to both levels before comparing, so small changes in a near-dark room don't make
  /// large ratios.
  static let floor = 20.0
  /// The display's own light reaches the sensor, so readings are ignored this long after it
  /// turns on or off.
  static let settleSeconds = 5.0

  public enum Change: Equatable {
    case brighter, darker
  }

  private var readings: [(time: Double, level: Double)] = []
  private var ignoredUntil = -Double.infinity

  public init() {}

  /// Forgets earlier readings and ignores new ones for `settleSeconds` from `time`.
  public mutating func settle(at time: Double) {
    readings = []
    ignoredUntil = time + Self.settleSeconds
  }

  /// Adds a reading taken at `time` (seconds, any steady clock) and returns the change it
  /// completes, if any. A change is reported once; later readings are compared with the new
  /// level.
  public mutating func add(_ level: Double, at time: Double) -> Change? {
    guard time >= ignoredUntil else { return nil }
    readings.removeAll { time - $0.time > Self.windowSeconds }
    readings.append((time, level))
    let ratio = (level + Self.floor) / (readings[0].level + Self.floor)
    let change: Change? =
      ratio >= Self.factor ? .brighter : ratio <= 1 / Self.factor ? .darker : nil
    if change != nil { readings = [(time, level)] }
    return change
  }
}
