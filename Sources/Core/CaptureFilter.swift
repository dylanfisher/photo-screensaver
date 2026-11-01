import Foundation
import Settings

/// The capture dates a timeframe takes in on a given day, as text compared with `taken_at`
/// (`YYYY-MM-DD HH:MM:SS`, ADR 0005). A prefix such as `2014-01` sorts before every date that
/// starts with it, so ranges compare whole text and use the `photos_taken_at` index.
public enum CaptureFilter: Equatable, Sendable {
  /// `taken_at` from `lower`, inclusive, up to `upper`, exclusive.
  case between(lower: String, upper: String)
  /// `MM-DD` from `first` through `last`, in any year. A `first` after `last` wraps around New
  /// Year.
  case daysOfYear(first: String, last: String)

  /// Nil for `.all`, which takes in every photo, with or without a date. `today` is read in
  /// `calendar`, so the days are the Mac's.
  public init?(_ timeframe: Timeframe, today: Date, calendar: Calendar) {
    switch timeframe {
    case .all:
      return nil
    case .onThisDay:
      let (_, month, day) = Self.parts(of: today, in: calendar)
      self = Self.daysAround(month: month, day: day, spread: Timeframe.onThisDayDays)
    case .lastMonths(let months):
      guard let start = calendar.date(byAdding: .month, value: -months, to: today),
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
      else { preconditionFailure("months back from today is a date") }
      // Through the end of today: a photo from later today, or a camera a few hours ahead,
      // still counts.
      self = .between(
        lower: Self.dayText(start, calendar: calendar),
        upper: Self.dayText(tomorrow, calendar: calendar))
    case .range(let from, let to):
      self = .between(lower: from.prefix, upper: to.next.prefix)
    }
  }

  /// The days `spread` either side of `month`/`day`, counted in a leap year, so Feb 29 is in
  /// the window around Feb 28 and Mar 1 of every year, and a Feb 29 today has its own window.
  static func daysAround(month: Int, day: Int, spread: Int) -> CaptureFilter {
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(secondsFromGMT: 0) else { preconditionFailure("GMT exists") }
    calendar.timeZone = utc
    guard let date = calendar.date(from: DateComponents(year: 2000, month: month, day: day)),
      let first = calendar.date(byAdding: .day, value: -spread, to: date),
      let last = calendar.date(byAdding: .day, value: spread, to: date)
    else { preconditionFailure("days around a date are dates") }
    func monthDay(_ date: Date) -> String {
      let (_, month, day) = parts(of: date, in: calendar)
      return String(format: "%02d-%02d", month, day)
    }
    return .daysOfYear(first: monthDay(first), last: monthDay(last))
  }

  /// `YYYY-MM-DD` of `date` in `calendar`.
  private static func dayText(_ date: Date, calendar: Calendar) -> String {
    let (year, month, day) = parts(of: date, in: calendar)
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  private static func parts(of date: Date, in calendar: Calendar) -> (Int, Int, Int) {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else {
      preconditionFailure("dateComponents gives the components asked for")
    }
    return (year, month, day)
  }
}
