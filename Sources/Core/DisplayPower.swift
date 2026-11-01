import CoreGraphics
import Foundation
import IOKit.pwr_mgt

public struct PowerError: Error, CustomStringConvertible {
  public let description: String
}

/// Display and system sleep control. Each `keep…` call holds or releases one power assertion.
public final class DisplayPower {
  private var displayAssertion: IOPMAssertionID?
  private var systemAssertion: IOPMAssertionID?

  public init() {}

  deinit {
    for id in [displayAssertion, systemAssertion].compactMap({ $0 }) { IOPMAssertionRelease(id) }
  }

  /// Keeps the display from sleeping on its idle timer while the slideshow shows.
  public func keepDisplayOn(_ on: Bool) throws {
    try hold(
      &displayAssertion, on, type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
      reason: "Showing photo slideshow")
  }

  /// Keeps the Mac awake while the display is off, so motion checks keep running.
  public func keepSystemAwake(_ on: Bool) throws {
    try hold(
      &systemAssertion, on, type: kIOPMAssertionTypePreventUserIdleSystemSleep,
      reason: "Checking for motion")
  }

  public func sleepDisplay() throws {
    let pmset = Process()
    pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    pmset.arguments = ["displaysleepnow"]
    try pmset.run()
    pmset.waitUntilExit()
    guard pmset.terminationStatus == 0 else {
      throw PowerError(description: "pmset displaysleepnow exited \(pmset.terminationStatus)")
    }
  }

  public func wakeDisplay() throws {
    var id = IOPMAssertionID(0)
    let result = IOPMAssertionDeclareUserActivity(
      "Motion detected" as CFString, kIOPMUserActiveLocal, &id)
    guard result == kIOReturnSuccess else {
      throw PowerError(description: "can't wake display (IOKit error \(result))")
    }
    IOPMAssertionRelease(id)
  }

  /// Mouse and trackpad input that counts as someone using the Mac.
  public static let pointerInputTypes: [CGEventType] = [
    .mouseMoved, .scrollWheel,
    .leftMouseDown, .rightMouseDown, .otherMouseDown,
    .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
  ]

  /// Input that counts as someone using the Mac. Leaves out brightness, volume and media keys
  /// (system-defined events) and the fn key alone (a modifier change), so adjusting the screen
  /// or sound doesn't end the slideshow.
  public static let userInputTypes: [CGEventType] = [.keyDown] + pointerInputTypes

  /// Seconds since the last `userInputTypes` event from anyone, or the last
  /// `pointerInputTypes` one when keys don't count.
  public static func secondsSinceUserInput(countingKeys: Bool) -> Double {
    (countingKeys ? userInputTypes : pointerInputTypes).map {
      CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
    }.min() ?? .infinity
  }

  private func hold(
    _ assertion: inout IOPMAssertionID?, _ on: Bool, type: String, reason: String
  ) throws {
    if on, assertion == nil {
      var id = IOPMAssertionID(0)
      let result = IOPMAssertionCreateWithName(
        type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
      guard result == kIOReturnSuccess else {
        throw PowerError(description: "can't create power assertion (IOKit error \(result))")
      }
      assertion = id
    } else if !on, let id = assertion {
      IOPMAssertionRelease(id)
      assertion = nil
    }
  }
}
