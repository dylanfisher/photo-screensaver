import Core
import Settings
import XCTest

final class BatteryWatchTests: XCTestCase {
  private let limited = BatteryWatchTests.battery(.limited)

  func testLimitedStopsAfterTheLimitOnBattery() {
    var watch = BatteryWatch()
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 100, battery: limited))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 100 + 599, battery: limited))
    XCTAssertTrue(watch.update(onBattery: true, showing: true, at: 100 + 600, battery: limited))
  }

  func testTimeOnPowerDoesNotCount() {
    var watch = BatteryWatch()
    XCTAssertFalse(watch.update(onBattery: false, showing: true, at: 0, battery: limited))
    XCTAssertFalse(watch.update(onBattery: false, showing: true, at: 3600, battery: limited))
    // Unplugged an hour into the slideshow: the limit counts from here.
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 3601, battery: limited))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 3601 + 599, battery: limited))
    XCTAssertTrue(watch.update(onBattery: true, showing: true, at: 3601 + 600, battery: limited))
  }

  func testPluggingInStartsTheCountAfresh() {
    var watch = BatteryWatch()
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 0, battery: limited))
    XCTAssertFalse(watch.update(onBattery: false, showing: true, at: 500, battery: limited))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 501, battery: limited))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 700, battery: limited))
  }

  func testAlwaysNeverStops() {
    var watch = BatteryWatch()
    let always = Self.battery(.always)
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 0, battery: always))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 86_400, battery: always))
    XCTAssertTrue(watch.startsOnItsOwn(onBattery: true, battery: always))
  }

  func testNeverStopsAtOnceAndDoesNotStart() {
    var watch = BatteryWatch()
    let never = Self.battery(.never)
    XCTAssertTrue(watch.update(onBattery: true, showing: true, at: 0, battery: never))
    XCTAssertFalse(watch.startsOnItsOwn(onBattery: true, battery: never))
    XCTAssertTrue(watch.startsOnItsOwn(onBattery: false, battery: never))
    XCTAssertFalse(BatteryWatch.startsByHand(onBattery: true, battery: never))
    XCTAssertTrue(BatteryWatch.startsByHand(onBattery: false, battery: never))
    XCTAssertTrue(BatteryWatch.startsByHand(onBattery: true, battery: limited))
  }

  func testAfterTheLimitItWaitsForTheUser() {
    var watch = BatteryWatch()
    XCTAssertTrue(watch.startsOnItsOwn(onBattery: true, battery: limited))
    _ = watch.update(onBattery: true, showing: true, at: 0, battery: limited)
    XCTAssertTrue(watch.update(onBattery: true, showing: true, at: 600, battery: limited))
    XCTAssertFalse(watch.startsOnItsOwn(onBattery: true, battery: limited))
    // On power it may start again.
    XCTAssertTrue(watch.startsOnItsOwn(onBattery: false, battery: limited))
    watch.userReturned()
    XCTAssertTrue(watch.startsOnItsOwn(onBattery: true, battery: limited))
  }

  func testNothingCountsWhileTheSlideshowIsDown() {
    var watch = BatteryWatch()
    XCTAssertFalse(watch.update(onBattery: true, showing: false, at: 0, battery: limited))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 3600, battery: limited))
    XCTAssertFalse(watch.update(onBattery: true, showing: true, at: 3600 + 599, battery: limited))
  }

  /// `mode`, with a 10-minute limit.
  private static func battery(_ mode: Settings.Battery.Mode) -> Settings.Battery {
    var battery = Settings.starter.battery
    battery.mode = mode
    battery.limitMinutes = 10
    return battery
  }
}
