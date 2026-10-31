import Core
import Primitives
import XCTest

final class MotionSampleTests: XCTestCase {
  let still = GrayFrame(width: 64, height: 48, pixels: Array(repeating: 100, count: 64 * 48))

  /// `still` with the top-left `count` pixels of the top-left 8×8 cell brightened.
  func changed(_ count: Int) -> GrayFrame {
    var pixels = still.pixels
    for i in 0..<count { pixels[(i / 8) * 64 + i % 8] = 200 }
    return GrayFrame(width: 64, height: 48, pixels: pixels)
  }

  func testStillFramesAreNotMotion() {
    var sample = MotionSample(threshold: 0.2)
    for _ in 0..<4 { sample.add(still) }
    XCTAssertFalse(sample.moved)
    XCTAssertEqual(sample.comparisons, 3)
  }

  func testSmallMovementInOneCellIsMotion() {
    // 16 pixels is a quarter of one cell, but under 1% of the frame.
    var sample = MotionSample(threshold: 0.2)
    sample.add(still)
    sample.add(changed(16))
    XCTAssertTrue(sample.moved)
  }

  func testSlowMovementAddsUpAgainstTheFirstFrame() {
    // Each step changes 8 pixels from the last, under the threshold; together they pass it.
    var sample = MotionSample(threshold: 0.2)
    for step in 0...2 { sample.add(changed(step * 8)) }
    XCTAssertEqual(sample.largestChange, 0.25)
    XCTAssertTrue(sample.moved)
  }
}
