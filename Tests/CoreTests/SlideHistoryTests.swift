import Core
import XCTest

final class SlideHistoryTests: XCTestCase {
  /// A history that has shown `ids` in order, with the last one on screen.
  func shown(_ ids: [Int64]) -> SlideHistory {
    var history = SlideHistory()
    for id in ids {
      history.forward()
      history.add(id)
    }
    return history
  }

  func testStartsWithANewPhoto() {
    var history = SlideHistory()
    XCTAssertEqual(history.target, .new)
    XCTAssertFalse(history.back())
    history.forward()
    XCTAssertEqual(history.target, .new)
  }

  func testAddedPhotoIsTheTarget() {
    XCTAssertEqual(shown([1, 2]).target, .photo(2))
  }

  func testBackThenForwardRevisitsBeforeNewPhotos() {
    var history = shown([1, 2, 3])
    XCTAssertTrue(history.back())
    XCTAssertEqual(history.target, .photo(2))
    XCTAssertTrue(history.back())
    XCTAssertEqual(history.target, .photo(1))
    XCTAssertFalse(history.back())
    XCTAssertEqual(history.target, .photo(1))
    history.forward()
    XCTAssertEqual(history.target, .photo(2))
    history.forward()
    XCTAssertEqual(history.target, .photo(3))
    history.forward()
    XCTAssertEqual(history.target, .new)
  }

  func testStepsPastTheEndAreOneNewPhoto() {
    var history = shown([1, 2])
    history.forward()
    history.forward()
    history.forward()
    XCTAssertEqual(history.target, .new)
    // Back from a new photo still loading is the photo on screen.
    XCTAssertTrue(history.back())
    XCTAssertEqual(history.target, .photo(2))
  }

  func testKeepsOnlyTheLatestPhotos() {
    var history = shown((1...Int64(SlideHistory.limit + 50)).map { $0 })
    var steps = 0
    while history.back() { steps += 1 }
    XCTAssertEqual(steps, SlideHistory.limit - 1)
    XCTAssertEqual(history.target, .photo(51))
  }
}
