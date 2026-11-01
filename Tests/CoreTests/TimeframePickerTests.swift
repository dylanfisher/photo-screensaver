import Foundation
import Settings
import XCTest

@testable import Core

final class TimeframePickerTests: XCTestCase {
  private typealias Range = TimeframePicker.MonthRange

  func testListsTheFixedChoicesThenYearsNewestFirst() {
    XCTAssertEqual(
      TimeframePicker.choices(years: [2014, 2021, 2009]),
      [
        .timeframe(.all), .timeframe(.onThisDay), .timeframe(.lastMonths(12)), .customRange,
        .timeframe(.year(2021)), .timeframe(.year(2014)), .timeframe(.year(2009)),
      ])
  }

  func testCountsEachChoice() {
    let counts = TimeframePicker.Counts(all: 100, onThisDay: 3, recent: 40, years: [2014: 25])
    XCTAssertEqual(counts.count(of: .all), 100)
    XCTAssertEqual(counts.count(of: .onThisDay), 3)
    XCTAssertEqual(counts.count(of: .lastMonths(12)), 40)
    XCTAssertEqual(counts.count(of: .year(2014)), 25)
    XCTAssertEqual(counts.count(of: .year(2015)), 0)
    XCTAssertNil(counts.count(of: .lastMonths(6)))
    XCTAssertNil(counts.count(of: .range(from: month(2014, 3), to: month(2014, 12))))
  }

  func testReadsTheCountsFromTheLibrary() throws {
    let library = try LibraryFixture()
    defer { try? library.remove() }
    try library.jpeg("a.jpg", properties: LibraryFixture.taken("2014:10:30 10:00:00"))
    try library.jpeg("b.jpg", properties: LibraryFixture.taken("2026:03:01 10:00:00"))
    try library.jpeg("c.jpg", properties: LibraryFixture.taken("2026:10:31 10:00:00"))
    try library.jpeg("undated.jpg")
    try library.scan()
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let today = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 11, day: 1)))

    let counts = try TimeframePicker.Counts(
      library: PhotoLibrary(at: library.database), today: today, calendar: utc)
    XCTAssertEqual(
      counts,
      TimeframePicker.Counts(all: 4, onThisDay: 2, recent: 2, years: [2014: 1, 2026: 2]))
  }

  func testARangeStepsByMonthsAndYears() {
    var range = Range(
      from: month(2014, 3), to: month(2015, 6), bounds: month(2000, 1)...month(2026, 11))
    range.step(.from, by: 1)
    XCTAssertEqual(range.from, month(2014, 4))
    range.step(.to, by: -12)
    XCTAssertEqual(range.to, month(2014, 6))
    XCTAssertEqual(range.timeframe, .range(from: month(2014, 4), to: month(2014, 6)))
  }

  func testAnEndMovedPastTheOtherTakesItAlong() {
    var range = Range(
      from: month(2014, 3), to: month(2014, 5), bounds: month(2000, 1)...month(2026, 11))
    range.step(.from, by: 12)
    XCTAssertEqual(range.from, month(2015, 3))
    XCTAssertEqual(range.to, month(2015, 3))
    range.step(.to, by: -24)
    XCTAssertEqual(range.from, month(2013, 3))
    XCTAssertEqual(range.to, month(2013, 3))
  }

  func testARangeStopsAtItsBounds() {
    var range = Range(
      from: month(2001, 2), to: month(2026, 10), bounds: month(2001, 1)...month(2026, 11))
    range.step(.from, by: -12)
    XCTAssertEqual(range.from, month(2001, 1))
    range.step(.to, by: 12)
    XCTAssertEqual(range.to, month(2026, 11))
  }

  func testARangeStartsOnTheCurrentRangeOrThisYear() {
    let today = month(2026, 11)
    let current = Range(
      current: .range(from: month(2014, 3), to: month(2015, 6)), years: [2009, 2026], today: today)
    XCTAssertEqual(current.timeframe, .range(from: month(2014, 3), to: month(2015, 6)))
    XCTAssertEqual(current.bounds, month(2009, 1)...month(2026, 12))

    let fresh = Range(current: .all, years: [2009], today: today)
    XCTAssertEqual(fresh.timeframe, .range(from: month(2026, 1), to: month(2026, 11)))
    XCTAssertEqual(fresh.bounds, month(2009, 1)...month(2026, 11))

    let empty = Range(current: .onThisDay, years: [], today: today)
    XCTAssertEqual(empty.bounds, month(2026, 11)...month(2026, 11))
  }

  func testARangeOpenedBeforeTheYearsArriveWidensWhenTheyDo() {
    let today = month(2026, 11)
    var range = Range(current: .all, years: [], today: today)
    XCTAssertEqual(range.bounds, today...today)
    range.rebound(years: [2009, 2014], today: today)
    XCTAssertEqual(range.bounds, month(2009, 1)...today)
    // The months stay where the narrow bounds held them, and can now move back.
    XCTAssertEqual(range.timeframe, .range(from: today, to: today))
    range.step(.from, by: -12 * 10)
    XCTAssertEqual(range.from, month(2016, 11))
    range.step(.from, by: -12 * 10)
    XCTAssertEqual(range.from, month(2009, 1))
  }

  private func month(_ year: Int, _ month: Int) -> CaptureMonth {
    CaptureMonth(year: year, month: month)
  }
}
