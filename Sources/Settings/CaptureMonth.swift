import Foundation

/// A calendar month, for choosing photos by when they were taken.
public struct CaptureMonth: Comparable, Hashable, Sendable {
  public let year: Int
  /// 1 to 12.
  public let month: Int

  public init(year: Int, month: Int) {
    precondition((1...12).contains(month), "month \(month) is not 1 to 12")
    self.year = year
    self.month = month
  }

  public static func < (a: CaptureMonth, b: CaptureMonth) -> Bool {
    (a.year, a.month) < (b.year, b.month)
  }

  /// `YYYY-MM`, which every `PhotoMetadata.takenAt` in this month starts with and sorts after.
  public var prefix: String { String(format: "%04d-%02d", year, month) }

  public var next: CaptureMonth {
    month == 12
      ? CaptureMonth(year: year + 1, month: 1) : CaptureMonth(year: year, month: month + 1)
  }
}
