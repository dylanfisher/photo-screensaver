import Settings
import XCTest

final class SettingsTests: XCTestCase {
  func testStarterRoundTrips() throws {
    XCTAssertEqual(try Settings.decode(Settings.starter.encoded()), Settings.starter)
  }

  func testMissingKeyNamesTheKey() throws {
    var json = try starterJSON()
    var motion = try XCTUnwrap(json["motion"] as? [String: Any])
    motion.removeValue(forKey: "sampleSeconds")
    json["motion"] = motion
    assertFails(json, containing: "motion.sampleSeconds")
  }

  func testMisspelledKeyFailsAsMissing() throws {
    var json = try starterJSON()
    json["kenburns"] = json.removeValue(forKey: "kenBurns")
    assertFails(json, containing: "kenBurns")
  }

  func testUnknownScalingFails() throws {
    var json = try starterJSON()
    json["scaling"] = "stretch"
    assertFails(json, containing: "scaling")
  }

  func testTransitionLongerThanSlideFails() throws {
    var json = try starterJSON()
    json["transitionSeconds"] = 20
    json["slideSeconds"] = 10
    assertFails(json, containing: "transitionSeconds")
  }

  func testThresholdOutOfRangeFails() throws {
    var json = try starterJSON()
    var motion = try XCTUnwrap(json["motion"] as? [String: Any])
    motion["threshold"] = 1.5
    json["motion"] = motion
    assertFails(json, containing: "motion.threshold")
  }

  func testQuickCheckLongerThanCheckIntervalFails() throws {
    var json = try starterJSON()
    var motion = try XCTUnwrap(json["motion"] as? [String: Any])
    motion["checkEveryMinutes"] = 1
    motion["quickCheckEverySeconds"] = 90
    json["motion"] = motion
    assertFails(json, containing: "motion.quickCheckEverySeconds")
  }

  func testCreateIfMissingWritesStarterOnlyOnce() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("config.json")

    try Settings.createIfMissing(at: url)
    XCTAssertEqual(try Settings.load(at: url), Settings.starter)

    var edited = Settings.starter
    edited.slideSeconds = 30
    try edited.encoded().write(to: url)
    try Settings.createIfMissing(at: url)
    XCTAssertEqual(try Settings.load(at: url), edited)
  }

  func testLoadMissingFileThrows() {
    XCTAssertThrowsError(try Settings.load(at: URL(fileURLWithPath: "/nonexistent/config.json")))
  }

  func testHugeDurationFails() throws {
    var json = try starterJSON()
    json["slideSeconds"] = 1e11
    assertFails(json, containing: "slideSeconds")
  }

  func testLibraryPathExpandsTilde() {
    var settings = Settings.starter
    settings.libraryPath = "~/Pictures"
    XCTAssertEqual(settings.libraryURL.path, NSHomeDirectory() + "/Pictures")
  }

  private func starterJSON() throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: Settings.starter.encoded()) as? [String: Any])
  }

  private func assertFails(
    _ json: [String: Any], containing text: String, line: UInt = #line
  ) {
    do {
      _ = try Settings.decode(JSONSerialization.data(withJSONObject: json))
      XCTFail("expected an error mentioning \(text)", line: line)
    } catch {
      XCTAssertTrue(
        "\(error)".contains(text), "\"\(error)\" does not mention \(text)", line: line)
    }
  }
}
