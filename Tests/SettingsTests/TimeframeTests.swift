import Foundation
import Settings
import XCTest

final class TimeframeTests: XCTestCase {
  func testEveryKindRoundTripsThroughItsJSON() throws {
    let cases: [(Timeframe, String)] = [
      (.all, #"{"kind":"all"}"#),
      (.onThisDay, #"{"kind":"onThisDay"}"#),
      (.lastMonths(12), #"{"kind":"lastMonths","months":12}"#),
      (.year(2014), #"{"from":"2014-01","kind":"range","to":"2014-12"}"#),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for (timeframe, json) in cases {
      XCTAssertEqual(String(decoding: try encoder.encode(timeframe), as: UTF8.self), json)
      XCTAssertEqual(try decode(json), timeframe)
    }
  }

  func testStarterShowsAllTime() {
    XCTAssertEqual(Settings.starter.timeframe, .all)
  }

  func testMissingTimeframeFails() throws {
    var json = try starterJSON()
    json["timeframe"] = nil
    assertFails(json, containing: "missing key \"timeframe\"")
  }

  func testRejectsBadTimeframesWithAReason() throws {
    let cases: [([String: Any], String)] = [
      (["kind": "everything"], "timeframe.kind"),
      (["months": 12], "missing key \"timeframe.kind\""),
      (["kind": "lastMonths"], "missing key \"timeframe.months\""),
      (["kind": "lastMonths", "months": 0], "timeframe.months must be from 1"),
      (["kind": "lastMonths", "months": 1201], "timeframe.months must be from 1"),
      (["kind": "range", "from": "2014-01"], "missing key \"timeframe.to\""),
      (["kind": "range", "from": "2014-1", "to": "2014-12"], "isn't a month like"),
      (["kind": "range", "from": "2014-13", "to": "2014-12"], "isn't a month like"),
      (["kind": "range", "from": "2015-01", "to": "2014-12"], "must not be after"),
      (["kind": "all", "months": 12], "\"all\" timeframes have no \"months\""),
      (["kind": "lastMonths", "monts": 12, "months": 12], "timeframe.monts"),
    ]
    for (timeframe, reason) in cases {
      var json = try starterJSON()
      json["timeframe"] = timeframe
      assertFails(json, containing: reason)
    }
  }

  func testTitles() {
    let march2014 = CaptureMonth(year: 2014, month: 3)
    let june = CaptureMonth(year: 2014, month: 6)
    XCTAssertEqual(Timeframe.all.title, "All time")
    XCTAssertEqual(Timeframe.onThisDay.title, "On this day")
    XCTAssertEqual(Timeframe.lastMonths(12).title, "Last 12 months")
    XCTAssertEqual(Timeframe.lastMonths(1).title, "Last month")
    XCTAssertEqual(Timeframe.year(2014).title, "2014")
    XCTAssertEqual(
      Timeframe.range(
        from: CaptureMonth(year: 2014, month: 1), to: CaptureMonth(year: 2016, month: 12)
      )
      .title, "2014 – 2016")
    XCTAssertEqual(Timeframe.range(from: march2014, to: march2014).title, "Mar 2014")
    XCTAssertEqual(Timeframe.range(from: march2014, to: june).title, "Mar – Jun 2014")
    XCTAssertEqual(
      Timeframe.range(from: march2014, to: CaptureMonth(year: 2015, month: 6)).title,
      "Mar 2014 – Jun 2015")
  }

  func testMonthsStepAcrossYears() {
    XCTAssertEqual(CaptureMonth(year: 2014, month: 12).next, CaptureMonth(year: 2015, month: 1))
    XCTAssertEqual(CaptureMonth(year: 2015, month: 1).previous, CaptureMonth(year: 2014, month: 12))
  }

  private func decode(_ json: String) throws -> Timeframe {
    try JSONDecoder().decode(Timeframe.self, from: Data(json.utf8))
  }

  private func starterJSON() throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: Settings.starter.encoded()) as? [String: Any])
  }

  private func assertFails(
    _ json: [String: Any], containing text: String, line: UInt = #line
  ) {
    do {
      _ = try Settings.decode(JSONSerialization.data(withJSONObject: json))
      XCTFail("expected an error mentioning \(text)", line: line)
    } catch {
      XCTAssertTrue(
        "\(error)".contains(text), "\"\(error)\" does not mention \(text)", line: line)
    }
  }
}
