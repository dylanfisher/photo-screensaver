import Primitives

/// The frames of one motion check, compared as they arrive. Each frame is compared with the one
/// before it, which catches quick movement, and with the first, so slow movement such as someone
/// shifting in a chair adds up over the check.
public struct MotionSample {
  /// 8×6 cells of 8×8 pixels at the detector's 64×48: small enough that a person across the room
  /// fills a good part of a cell, large enough that a few noisy pixels don't.
  public static let grid = (columns: 8, rows: 6)

  /// Fraction of any one grid cell (0–1) that must change to count as motion.
  public let threshold: Double
  public private(set) var largestChange = 0.0
  public private(set) var comparisons = 0
  private var first: GrayFrame?
  private var previous: GrayFrame?

  public init(threshold: Double) {
    self.threshold = threshold
  }

  public var moved: Bool { largestChange >= threshold }

  public mutating func add(_ frame: GrayFrame) {
    for earlier in [previous, first].compactMap({ $0 }) {
      largestChange = max(
        largestChange,
        frame.largestCellChange(
          from: earlier, columns: Self.grid.columns, rows: Self.grid.rows))
    }
    if previous != nil { comparisons += 1 }
    if first == nil { first = frame }
    previous = frame
  }
}
