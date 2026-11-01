import Foundation
import Settings

/// What the timeframe picker offers: all time, on this day, the last 12 months, a custom range
/// of months, and each year that has photos, with how many photos each shows.
public enum TimeframePicker {
  /// The months "last months" covers in the picker. The setting itself takes any number.
  public static let recentMonths = 12

  public enum Choice: Equatable {
    case timeframe(Timeframe)
    /// Opens the month range, which shows its own count.
    case customRange
  }

  /// The fixed choices first, so they keep their place when the years arrive with the counts,
  /// then each year with photos, newest first.
  public static func choices(years: [Int]) -> [Choice] {
    [.timeframe(.all), .timeframe(.onThisDay), .timeframe(.lastMonths(recentMonths)), .customRange]
      + years.sorted(by: >).map { .timeframe(.year($0)) }
  }

  /// How many photos each choice shows, read in one go.
  public struct Counts: Equatable, Sendable {
    /// Every photo that can be shown, dated or not.
    public var all: Int
    public var onThisDay: Int
    /// The last `recentMonths` months.
    public var recent: Int
    /// Photos taken in each year, for years with any.
    public var years: [Int: Int]

    public init(all: Int, onThisDay: Int, recent: Int, years: [Int: Int]) {
      self.all = all
      self.onThisDay = onThisDay
      self.recent = recent
      self.years = years
    }

    /// Reads every count from `library`. "On this day" and the years read every dated row,
    /// tens of milliseconds for 150,000 photos, so not on the main thread.
    public init(library: PhotoLibrary, today: Date, calendar: Calendar) throws {
      func count(_ timeframe: Timeframe) throws -> Int {
        try library.count(matching: CaptureFilter(timeframe, today: today, calendar: calendar))
      }
      self.init(
        all: try library.count(), onThisDay: try count(.onThisDay),
        recent: try count(.lastMonths(TimeframePicker.recentMonths)),
        years: try library.yearCounts())
    }

    /// The count for one of the picker's timeframes, or nil for another, like a custom range.
    public func count(of timeframe: Timeframe) -> Int? {
      switch timeframe {
      case .all: return all
      case .onThisDay: return onThisDay
      case .lastMonths(let months) where months == TimeframePicker.recentMonths: return recent
      case .range(let from, _) where timeframe == .year(from.year):
        return years[from.year] ?? 0
      case .lastMonths, .range: return nil
      }
    }
  }

  /// The months a custom range runs between, stepped a month or a year at a time, and kept
  /// in order and within `bounds`.
  public struct MonthRange: Equatable {
    public enum End {
      case from, to
    }

    public private(set) var from: CaptureMonth
    public private(set) var to: CaptureMonth
    public private(set) var bounds: ClosedRange<CaptureMonth>

    /// `from` and `to` are moved into `bounds`, and `to` up to `from`.
    public init(from: CaptureMonth, to: CaptureMonth, bounds: ClosedRange<CaptureMonth>) {
      self.bounds = bounds
      self.from = from.clamped(to: bounds)
      self.to = max(to.clamped(to: bounds), self.from)
    }

    /// Bounds from January of the oldest year with photos to the later of this month and
    /// December of the newest year, since a camera's clock can be ahead. Starts on the
    /// timeframe's months if it's a range, or else on this year so far.
    public init(current: Timeframe, years: [Int], today: CaptureMonth) {
      let bounds = Self.bounds(years: years, today: today)
      if case .range(let from, let to) = current {
        self.init(from: from, to: to, bounds: bounds)
      } else {
        self.init(from: CaptureMonth(year: today.year, month: 1), to: today, bounds: bounds)
      }
    }

    public var timeframe: Timeframe { .range(from: from, to: to) }

    /// Changes the bounds for `years`, as when the years arrive after the range opened,
    /// keeping the months chosen as far as the new bounds allow.
    public mutating func rebound(years: [Int], today: CaptureMonth) {
      self = MonthRange(from: from, to: to, bounds: Self.bounds(years: years, today: today))
    }

    private static func bounds(years: [Int], today: CaptureMonth) -> ClosedRange<CaptureMonth> {
      let oldest = years.min().map { CaptureMonth(year: $0, month: 1) } ?? today
      let newest = max(years.max().map { CaptureMonth(year: $0, month: 12) } ?? today, today)
      return min(oldest, today)...newest
    }

    /// Moves one end by `months`, stopping at the bounds. An end moved past the other takes it
    /// along.
    public mutating func step(_ end: End, by months: Int) {
      switch end {
      case .from:
        from = from.adding(months: months).clamped(to: bounds)
        to = max(to, from)
      case .to:
        to = to.adding(months: months).clamped(to: bounds)
        from = min(from, to)
      }
    }
  }
}

extension CaptureMonth {
  fileprivate func clamped(to bounds: ClosedRange<CaptureMonth>) -> CaptureMonth {
    min(max(self, bounds.lowerBound), bounds.upperBound)
  }
}
