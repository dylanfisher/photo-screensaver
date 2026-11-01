/// Picks how many files to read at once from a network volume, from the throughput measured at
/// each level. The best number depends on the server's disks and the network between, and too
/// many reads queue behind each other and slow everyone else's reads from the same share, so it
/// looks for the fewest readers that reach the best throughput.
///
/// It reads no clock and does no I/O: the caller measures each window and passes it to
/// `observe`, so tests drive it with made-up throughput curves.
public struct ReadConcurrency: Sendable, Equatable {
  /// A doubling that gains no more than this is no gain, so the climb stops. Anything more keeps
  /// it climbing: a level too high costs the server a little, one too low costs most of the speed.
  static let climbGain = 0.05
  /// How much better a probe above the held level must do to replace it.
  static let probeGain = 0.08
  /// How much worse a probe below the held level may do and still replace it, so the level
  /// drifts down to where throughput stops rising.
  static let probeLoss = 0.05
  /// Windows at the held level between probes.
  static let holdWindows = 2
  /// A held level whose throughput falls below this share of its estimate, or whose seconds per
  /// file rise past `latencyRise` times, for `collapseWindows` windows in a row, means the server
  /// got slower, so the level halves. One such window is as likely a few slow files.
  static let collapse = 0.6
  static let latencyRise = 2.0
  static let collapseWindows = 2

  public enum Phase: Sendable, Equatable {
    /// Doubling while each doubling helps. `from` is the level before.
    case climbing(from: Int?)
    case holding(windowsLeft: Int, probeUp: Bool)
    /// Trying one window at `level` instead of the held `from`.
    case probing(from: Int, up: Bool)
  }

  /// One window's measurement at the current level.
  public struct Window: Sendable, Equatable {
    public var filesPerSecond: Double
    public var secondsPerFile: Double

    public init(filesPerSecond: Double, secondsPerFile: Double) {
      self.filesPerSecond = filesPerSecond
      self.secondsPerFile = secondsPerFile
    }
  }

  public let range: ClosedRange<Int>
  public private(set) var level: Int
  public private(set) var phase = Phase.climbing(from: nil)
  /// Each level settled on, in order, from the start. Probes that were undone aren't in it.
  public private(set) var trace: [Int]
  /// The held level's measurements, smoothed over the windows it was held.
  private var baseline: Window?
  private var lastClimb: Window?
  /// Held windows in a row that looked like the server got slower.
  private var collapsed = 0

  public init(range: ClosedRange<Int>, start: Int) {
    self.range = range
    level = min(max(start, range.lowerBound), range.upperBound)
    trace = [level]
  }

  /// Takes the window just measured at `level` and moves `level` for the next one.
  public mutating func observe(_ window: Window) {
    switch phase {
    case .climbing(let from):
      if let from, let previous = lastClimb,
        window.filesPerSecond <= previous.filesPerSecond * (1 + Self.climbGain)
      {
        // The doubling didn't help, so the level below is as good and costs the server less.
        settle(on: from, previous)
      } else if level == range.upperBound {
        settle(on: level, window)
      } else {
        lastClimb = window
        phase = .climbing(from: level)
        level = min(level * 2, range.upperBound)
        trace.append(level)
      }
    case .holding(let windowsLeft, let probeUp):
      guard let held = baseline else { preconditionFailure("holding without a baseline") }
      if window.filesPerSecond < held.filesPerSecond * Self.collapse
        || window.secondsPerFile > held.secondsPerFile * Self.latencyRise
      {
        collapsed += 1
        if collapsed >= Self.collapseWindows { backOff() }
        // Kept out of the estimate, which it would drag down.
        return
      }
      collapsed = 0
      baseline = Window(
        filesPerSecond: (held.filesPerSecond + window.filesPerSecond) / 2,
        secondsPerFile: (held.secondsPerFile + window.secondsPerFile) / 2)
      if windowsLeft > 1 {
        phase = .holding(windowsLeft: windowsLeft - 1, probeUp: probeUp)
      } else {
        probe(up: probeUp)
      }
    case .probing(let from, let up):
      guard let held = baseline else { preconditionFailure("probing without a baseline") }
      let better =
        up
        ? window.filesPerSecond > held.filesPerSecond * (1 + Self.probeGain)
        : window.filesPerSecond >= held.filesPerSecond * (1 - Self.probeLoss)
      if better {
        // Keep going the same way next time.
        settle(on: level, window, probeUp: up)
      } else {
        level = from
        phase = .holding(windowsLeft: Self.holdWindows, probeUp: !up)
      }
    }
  }

  private mutating func settle(on settled: Int, _ measured: Window, probeUp: Bool = false) {
    level = settled
    if trace.last != settled { trace.append(settled) }
    baseline = measured
    lastClimb = nil
    collapsed = 0
    phase = .holding(windowsLeft: Self.holdWindows, probeUp: probeUp)
  }

  private mutating func probe(up: Bool) {
    let step = max(1, level / 4)
    let target = up ? min(level + step, range.upperBound) : max(level - step, range.lowerBound)
    if target == level {
      // At a bound: probe the other way, unless the range is one level.
      let other = up ? max(level - step, range.lowerBound) : min(level + step, range.upperBound)
      guard other != level else {
        phase = .holding(windowsLeft: Self.holdWindows, probeUp: up)
        return
      }
      phase = .probing(from: level, up: !up)
      level = other
    } else {
      phase = .probing(from: level, up: up)
      level = target
    }
  }

  /// The server slowed down, perhaps from other clients, so what was measured before no longer
  /// holds: halve and climb again from there.
  private mutating func backOff() {
    level = max(level / 2, range.lowerBound)
    if trace.last != level { trace.append(level) }
    baseline = nil
    lastClimb = nil
    collapsed = 0
    phase = .climbing(from: nil)
  }
}
