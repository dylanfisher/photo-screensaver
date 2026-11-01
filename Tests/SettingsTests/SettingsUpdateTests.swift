import Settings
import XCTest

final class SettingsUpdateTests: XCTestCase {
  private var dir: URL!
  private var url: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    url = dir.appendingPathComponent("config.json")
    try Settings.starter.encoded().write(to: url)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: dir)
  }

  func testWritesTheChangeInTheFilesFormat() throws {
    XCTAssertTrue(try Settings.update(at: url) { $0.slideSeconds = 30 })
    var expected = Settings.starter
    expected.slideSeconds = 30
    XCTAssertEqual(try Data(contentsOf: url), try expected.encoded())
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["config.json"])
  }

  func testChangeThatChangesNothingWritesNothing() throws {
    // Compact, as an editor might leave it: a write would pretty-print it.
    let compact = try JSONSerialization.data(
      withJSONObject: JSONSerialization.jsonObject(with: Settings.starter.encoded()))
    try compact.write(to: url)
    let old = Date(timeIntervalSince1970: 1_000_000)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

    XCTAssertFalse(try Settings.update(at: url) { $0.slideSeconds = Settings.starter.slideSeconds })

    XCTAssertEqual(try Data(contentsOf: url), compact)
    XCTAssertEqual(try modificationDate(), old)
  }

  func testRedoesTheChangeOnAFileChangedMeanwhile() throws {
    var calls = 0
    try Settings.update(at: url) { settings in
      calls += 1
      if calls == 1 {
        // An editor saves between the read and the write.
        var edited = Settings.starter
        edited.idleMinutes = 9
        try edited.encoded().write(to: url)
      }
      settings.slideSeconds = 30
    }
    XCTAssertEqual(calls, 2)
    let saved = try Settings.load(at: url)
    XCTAssertEqual(saved.idleMinutes, 9)
    XCTAssertEqual(saved.slideSeconds, 30)
  }

  func testGivesUpWhenTheFileChangesUnderEveryTry() throws {
    var calls = 0
    XCTAssertThrowsError(
      try Settings.update(at: url) { settings in
        calls += 1
        var edited = Settings.starter
        edited.idleMinutes = Double(calls)
        try edited.encoded().write(to: url)
        settings.slideSeconds = 30
      }
    ) { XCTAssertTrue("\($0)".contains("changed while it was being saved"), "\($0)") }
    XCTAssertEqual(calls, 3)
    XCTAssertEqual(try Settings.load(at: url).idleMinutes, 3)
    XCTAssertEqual(try Settings.load(at: url).slideSeconds, Settings.starter.slideSeconds)
  }

  func testBrokenFileIsLeftAlone() throws {
    let broken = Data("{\"idleMinutes\": 5".utf8)
    try broken.write(to: url)
    var called = false
    XCTAssertThrowsError(try Settings.update(at: url) { _ in called = true })
    XCTAssertFalse(called)
    XCTAssertEqual(try Data(contentsOf: url), broken)
  }

  func testInvalidChangeIsNotWritten() throws {
    XCTAssertThrowsError(try Settings.update(at: url) { $0.transitionSeconds = 400 }) {
      XCTAssertTrue("\($0)".contains("transitionSeconds"), "\($0)")
    }
    XCTAssertEqual(try Data(contentsOf: url), try Settings.starter.encoded())
  }

  func testMissingFileSaysSoInWords() throws {
    try FileManager.default.removeItem(at: url)
    XCTAssertThrowsError(try Settings.update(at: url) { $0.slideSeconds = 30 }) { error in
      XCTAssertTrue("\(error)".hasPrefix("config.json couldn't be read: "), "\(error)")
      XCTAssertFalse("\(error)".contains("Error Domain"), "\(error)")
    }
  }

  func testKeepsOwnerOnlyPermissions() throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    try Settings.update(at: url) { $0.slideSeconds = 30 }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testKeepsPermissions() throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
    try Settings.update(at: url) { $0.slideSeconds = 30 }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o640)
  }

  func testWritesThroughASymbolicLink() throws {
    let link = dir.appendingPathComponent("link.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    try Settings.update(at: link) { $0.slideSeconds = 30 }
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: link.path), url.path)
    XCTAssertEqual(try Settings.load(at: url).slideSeconds, 30)
  }

  private func modificationDate() throws -> Date? {
    try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
  }
}
