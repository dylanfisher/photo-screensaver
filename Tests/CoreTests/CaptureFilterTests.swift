import Foundation
import Settings
import XCTest

@testable import Core

final class CaptureFilterTests: XCTestCase {
  func testAllTimeHasNoFilter() {
    XCTAssertNil(CaptureFilter(.all, today: day(2026, 11, 1), calendar: utc))
  }

  func testARangeRunsToTheStartOfTheMonthAfter() {
    XCTAssertEqual(
      CaptureFilter(.year(2014), today: day(2026, 11, 1), calendar: utc),
      .between(lower: "2014-01", upper: "2015-01"))
    let range = Timeframe.range(
      from: CaptureMonth(year: 2019, month: 3), to: CaptureMonth(year: 2020, month: 12))
    XCTAssertEqual(
      CaptureFilter(range, today: day(2026, 11, 1), calendar: utc),
      .between(lower: "2019-03", upper: "2021-01"))
  }

  func testLastMonthsRunsFromThatDateThroughToday() {
    XCTAssertEqual(
      CaptureFilter(.lastMonths(12), today: day(2026, 11, 1), calendar: utc),
      .between(lower: "2025-11-01", upper: "2026-11-02"))
    // A month back from Mar 31 is the last day of February.
    XCTAssertEqual(
      CaptureFilter(.lastMonths(1), today: day(2026, 3, 31), calendar: utc),
      .between(lower: "2026-02-28", upper: "2026-04-01"))
  }

  func testOnThisDayTakesInThreeDaysEitherSide() {
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: day(2026, 11, 1), calendar: utc),
      .daysOfYear(first: "10-29", last: "11-04"))
  }

  func testOnThisDayWrapsAroundNewYear() {
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: day(2026, 12, 30), calendar: utc),
      .daysOfYear(first: "12-27", last: "01-02"))
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: day(2027, 1, 2), calendar: utc),
      .daysOfYear(first: "12-30", last: "01-05"))
  }

  func testOnThisDayCountsFebruary29InEveryYear() {
    // 2026 has no Feb 29, but photos from leap years taken on it are in the window.
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: day(2026, 2, 28), calendar: utc),
      .daysOfYear(first: "02-25", last: "03-02"))
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: day(2026, 3, 1), calendar: utc),
      .daysOfYear(first: "02-27", last: "03-04"))
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: day(2028, 2, 29), calendar: utc),
      .daysOfYear(first: "02-26", last: "03-03"))
  }

  func testTodayIsTheCalendarsDay() throws {
    // 23:30 UTC on Oct 31 is already Nov 1 in Tokyo.
    var tokyo = Calendar(identifier: .gregorian)
    tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
    let late = day(2026, 10, 31).addingTimeInterval(23.5 * 3600)
    XCTAssertEqual(
      CaptureFilter(.onThisDay, today: late, calendar: tokyo),
      .daysOfYear(first: "10-29", last: "11-04"))
  }

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
  }
}
