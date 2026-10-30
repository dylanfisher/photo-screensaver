import Primitives
import XCTest

final class GrayFrameTests: XCTestCase {
  func testIdenticalFramesHaveNoChange() {
    let frame = GrayFrame(width: 4, height: 4, pixels: Array(repeating: 100, count: 16))
    XCTAssertEqual(frame.changedFraction(from: frame), 0)
  }

  func testSmallNoiseIsIgnored() {
    let a = GrayFrame(width: 2, height: 2, pixels: [100, 100, 100, 100])
    let b = GrayFrame(width: 2, height: 2, pixels: [110, 90, 120, 100])
    XCTAssertEqual(a.changedFraction(from: b), 0)
  }

  func testCountsChangedPixels() {
    let a = GrayFrame(width: 2, height: 2, pixels: [0, 0, 0, 0])
    let b = GrayFrame(width: 2, height: 2, pixels: [200, 0, 0, 200])
    XCTAssertEqual(a.changedFraction(from: b), 0.5)
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
