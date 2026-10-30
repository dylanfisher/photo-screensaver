import Primitives
import XCTest

final class ShuffleQueueTests: XCTestCase {
  func testShowsEveryElementOnceBeforeRepeating() {
    var queue = ShuffleQueue(Array(0..<50))
    let firstPass = (0..<50).compactMap { _ in queue.next() }
    XCTAssertEqual(Set(firstPass), Set(0..<50))
  }

  func testEmptyQueueReturnsNil() {
    var queue = ShuffleQueue([Int]())
    XCTAssertNil(queue.next())
  }
}
