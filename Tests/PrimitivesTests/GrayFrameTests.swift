import Primitives
import XCTest

final class GrayFrameTests: XCTestCase {
  func testIdenticalFramesHaveNoChange() {
    let frame = GrayFrame(width: 4, height: 4, pixels: Array(repeating: 100, count: 16))
    XCTAssertEqual(frame.largestCellChange(from: frame, columns: 2, rows: 2), 0)
  }

  func testSmallNoiseIsIgnored() {
    let a = GrayFrame(width: 2, height: 2, pixels: [100, 100, 100, 100])
    let b = GrayFrame(width: 2, height: 2, pixels: [110, 90, 120, 100])
    XCTAssertEqual(a.largestCellChange(from: b, columns: 1, rows: 1), 0)
  }

  func testReportsTheMostChangedCell() {
    // 4×4 in a 2×2 grid; 2 of the 4 pixels in the top-left cell change. Across the whole frame
    // that's only 2 of 16.
    var pixels = [UInt8](repeating: 100, count: 16)
    let a = GrayFrame(width: 4, height: 4, pixels: pixels)
    pixels[0] = 200
    pixels[5] = 200
    let b = GrayFrame(width: 4, height: 4, pixels: pixels)
    XCTAssertEqual(a.largestCellChange(from: b, columns: 2, rows: 2), 0.5)
  }

  func testUniformBrightnessShiftIsIgnored() {
    let a = GrayFrame(width: 4, height: 4, pixels: Array(repeating: 60, count: 16))
    let b = GrayFrame(width: 4, height: 4, pixels: Array(repeating: 140, count: 16))
    XCTAssertEqual(a.largestCellChange(from: b, columns: 2, rows: 2), 0)
  }

  func testSamplingSkipsRowPadding() throws {
    // 4×2 source with 2 bytes of padding per row; padding must never be sampled.
    let source: [UInt8] = [
      10, 20, 30, 40, 255, 255,
      50, 60, 70, 80, 255, 255,
    ]
    let frame = try source.withUnsafeBufferPointer {
      GrayFrame(
        sampling: try XCTUnwrap($0.baseAddress), width: 4, height: 2, bytesPerRow: 6,
        toWidth: 2, height: 2)
    }
    XCTAssertEqual(frame.pixels, [10, 30, 50, 70])
  }
}
