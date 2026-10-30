import Core
import XCTest

final class FramingTests: XCTestCase {
  let screen = CGSize(width: 2560, height: 1600)

  func testFillCoversTheScreen() {
    let shown = displayedSize(photo: CGSize(width: 3000, height: 3000), in: screen, scaling: .fill)
    XCTAssertEqual(shown, CGSize(width: 2560, height: 2560))
  }

  func testFitShowsTheWholePhoto() {
    let shown = displayedSize(photo: CGSize(width: 3000, height: 3000), in: screen, scaling: .fit)
    XCTAssertEqual(shown, CGSize(width: 1600, height: 1600))
  }

  func testDecodesAtTwiceDisplayedSize() {
    let edge = decodeLongEdge(
      photo: CGSize(width: 12000, height: 8000), screenPixels: screen, scaling: .fill)
    // 3:2 is wider than 16:10, so fill matches the width: 2560 shown, 5120 decoded.
    XCTAssertEqual(edge, 5120)
  }

  func testPortraitFillDecodesPastScreenLongEdge() {
    // A portrait filling a landscape screen is shown 2560 wide, so 3840 tall; 2× is 7680.
    let edge = decodeLongEdge(
      photo: CGSize(width: 6000, height: 9000), screenPixels: screen, scaling: .fill)
    XCTAssertEqual(edge, 7680)
  }

  func testDecodeIsCappedAtTheOriginal() {
    let edge = decodeLongEdge(
      photo: CGSize(width: 4000, height: 3000), screenPixels: screen, scaling: .fill)
    XCTAssertEqual(edge, 4000)
  }
}
