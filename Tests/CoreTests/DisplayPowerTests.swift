import Core
import CoreGraphics
import XCTest

final class DisplayPowerTests: XCTestCase {
  func testBrightnessVolumeAndFnKeysAreNotUserInput() {
    let types = DisplayPower.userInputTypes.map(\.rawValue)
    // 14 is NX_SYSDEFINED, which CGEventType has no case for.
    XCTAssertFalse(types.contains(14), "system-defined keys")
    XCTAssertFalse(types.contains(CGEventType.flagsChanged.rawValue), "modifier keys")
    XCTAssertTrue(types.contains(CGEventType.keyDown.rawValue))
    XCTAssertTrue(types.contains(CGEventType.mouseMoved.rawValue))
  }

  func testPointerInputLeavesOutKeys() {
    let types = DisplayPower.pointerInputTypes.map(\.rawValue)
    XCTAssertFalse(types.contains(CGEventType.keyDown.rawValue))
    XCTAssertTrue(types.contains(CGEventType.leftMouseDown.rawValue))
    XCTAssertTrue(types.contains(CGEventType.mouseMoved.rawValue))
  }
}
