import Core
import XCTest

final class LightWatchTests: XCTestCase {
  /// Feeds one reading per second from `start` and returns the changes reported.
  func changes(_ levels: [Double], watch: inout LightWatch, start: Double = 0)
    -> [LightWatch.Change?]
  {
    levels.enumerated().map { watch.add($0.element, at: start + Double($0.offset)) }
  }

  func testSteadyLightIsNoChange() {
    var watch = LightWatch()
    XCTAssertEqual(changes([3640, 3650, 3630, 3640], watch: &watch), [nil, nil, nil, nil])
  }

  func testLampOnIsBrighter() {
    var watch = LightWatch()
    XCTAssertEqual(changes([400, 400, 1200], watch: &watch), [nil, nil, .brighter])
  }

  func testLampOffIsDarker() {
    var watch = LightWatch()
    XCTAssertEqual(changes([1200, 1200, 300], watch: &watch), [nil, nil, .darker])
  }

  func testAChangeIsReportedOnce() {
    var watch = LightWatch()
    XCTAssertEqual(changes([400, 1200, 1200, 1200], watch: &watch), [nil, .brighter, nil, nil])
  }

  func testSlowDriftIsNoChange() {
    // Doubles over 20 s, but never by 1.5× within 5 s.
    var watch = LightWatch()
    let levels = (0...20).map { 500 * (1 + Double($0) / 20) }
    XCTAssertEqual(changes(levels, watch: &watch), Array(repeating: nil, count: 21))
  }

  func testSmallChangesInTheDarkAreNoChange() {
    var watch = LightWatch()
    XCTAssertEqual(changes([2, 2, 8], watch: &watch), [nil, nil, nil])
  }

  func testReadingsAreIgnoredWhileTheDisplaySettles() {
    var watch = LightWatch()
    _ = changes([400, 400], watch: &watch)
    watch.settle(at: 2)
    // The screen's light change at 2–6 s is ignored, and not used as a baseline later.
    XCTAssertEqual(
      changes([1200, 1200, 1200, 1200, 1200], watch: &watch, start: 2),
      Array(repeating: nil, count: 5))
    XCTAssertEqual(watch.add(1200, at: 7), nil)
    XCTAssertEqual(watch.add(400, at: 8), .darker)
  }
}
