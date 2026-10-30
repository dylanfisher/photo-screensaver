import Core
import XCTest

final class KenBurnsTests: XCTestCase {
  let screen = CGSize(width: 1280, height: 800)

  func testFillNeverRevealsTheBackground() {
    var generator = SeededGenerator(seed: 1)
    for photo in [
      CGSize(width: 3, height: 2), CGSize(width: 2, height: 3), CGSize(width: 1, height: 1),
    ] {
      for _ in 0..<200 {
        let move = KenBurns.random(photo: photo, view: screen, scaling: .fill, using: &generator)
        for frame in [move.start, move.end] {
          let shown = displayedSize(photo: photo, in: screen, scaling: .fill)
          XCTAssertLessThanOrEqual(
            abs(frame.offset.x), (shown.width * frame.scale - screen.width) / 2 + 0.001)
          XCTAssertLessThanOrEqual(
            abs(frame.offset.y), (shown.height * frame.scale - screen.height) / 2 + 0.001)
        }
      }
    }
  }

  func testFitDoesNotPanAcrossLetterboxedAxis() {
    var generator = SeededGenerator(seed: 2)
    // A square photo fit to 1280×800 is 800×800 shown: never wide enough to pan sideways.
    for _ in 0..<200 {
      let move = KenBurns.random(
        photo: CGSize(width: 1, height: 1), view: screen, scaling: .fit, using: &generator)
      XCTAssertEqual(move.start.offset.x, 0)
      XCTAssertEqual(move.end.offset.x, 0)
    }
  }

  func testZoomsBothWays() {
    var generator = SeededGenerator(seed: 3)
    let moves = (0..<50).map { _ in
      KenBurns.random(
        photo: CGSize(width: 3, height: 2), view: screen, scaling: .fill, using: &generator)
    }
    XCTAssertTrue(moves.contains { $0.end.scale > $0.start.scale })
    XCTAssertTrue(moves.contains { $0.end.scale < $0.start.scale })
  }
}

/// Deterministic generator so failures reproduce (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
