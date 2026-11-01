import Core
import Settings
import XCTest

final class SettingsModelTests: XCTestCase {
  @MainActor
  func testEachFieldWritesItsKey() throws {
    let (model, url) = try makeModel()
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let fields: [(String, () -> Void, (Settings) -> Bool)] = [
      (
        "library in home", { model.setLibrary(home.appendingPathComponent("Pictures")) },
        { $0.libraryPath == "~/Pictures" }
      ),
      (
        "library elsewhere", { model.setLibrary(URL(fileURLWithPath: "/Volumes/nas/photos")) },
        { $0.libraryPath == "/Volumes/nas/photos" }
      ),
      ("idleMinutes", { model.setNumber(\.idleMinutes, from: "10") }, { $0.idleMinutes == 10 }),
      ("slideSeconds", { model.set(\.slideSeconds, to: 60) }, { $0.slideSeconds == 60 }),
      (
        "transitionSeconds", { model.setNumber(\.transitionSeconds, from: " 2.5 ") },
        { $0.transitionSeconds == 2.5 }
      ),
      ("scaling", { model.set(\.scaling, to: .fit) }, { $0.scaling == .fit }),
      ("orientation", { model.set(\.orientation, to: .portrait) }, { $0.orientation == .portrait }),
      ("kenBurns", { model.set(\.kenBurns, to: false) }, { !$0.kenBurns }),
      ("preloadCount", { model.setCount(\.preloadCount, from: "4") }, { $0.preloadCount == 4 }),
      ("motion.enabled", { model.set(\.motion.enabled, to: true) }, { $0.motion.enabled }),
      (
        "motion.checkEveryMinutes", { model.setNumber(\.motion.checkEveryMinutes, from: "7") },
        { $0.motion.checkEveryMinutes == 7 }
      ),
      (
        "motion.quickCheckEverySeconds",
        { model.setNumber(\.motion.quickCheckEverySeconds, from: "20") },
        { $0.motion.quickCheckEverySeconds == 20 }
      ),
      (
        "motion.sampleSeconds", { model.setNumber(\.motion.sampleSeconds, from: "3") },
        { $0.motion.sampleSeconds == 3 }
      ),
      (
        "motion.useLightSensor", { model.set(\.motion.useLightSensor, to: false) },
        { !$0.motion.useLightSensor }
      ),
      (
        "motion.threshold", { model.setNumber(\.motion.threshold, from: "0.35") },
        { $0.motion.threshold == 0.35 }
      ),
      ("offHours.enabled", { model.set(\.offHours.enabled, to: true) }, { $0.offHours.enabled }),
      (
        "offHours.start", { model.set(\.offHours.start, to: "22:00") },
        { $0.offHours.start == "22:00" }
      ),
      ("offHours.end", { model.set(\.offHours.end, to: "07:30") }, { $0.offHours.end == "07:30" }),
      (
        "timeframe on this day", { model.setTimeframeKind(.onThisDay, today: self.today) },
        { $0.timeframe == .onThisDay }
      ),
      (
        "timeframe last months",
        { model.setTimeframeKind(.lastMonths, today: self.today) },
        { $0.timeframe == .lastMonths(TimeframePicker.recentMonths) }
      ),
      ("timeframe months", { model.setMonths(from: "24") }, { $0.timeframe == .lastMonths(24) }),
      (
        "timeframe range", { model.setTimeframeKind(.range, today: self.today) },
        { $0.timeframe == .range(from: self.month(2026, 1), to: self.today) }
      ),
      (
        "timeframe from", { model.setRange(first: true, from: "2014-03") },
        { $0.timeframe == .range(from: self.month(2014, 3), to: self.today) }
      ),
      (
        "timeframe to", { model.setRange(first: false, from: "2015-06") },
        { $0.timeframe == .range(from: self.month(2014, 3), to: self.month(2015, 6)) }
      ),
      (
        "timeframe all", { model.setTimeframeKind(.all, today: self.today) },
        { $0.timeframe == .all }
      ),
    ]
    for (name, change, check) in fields {
      change()
      XCTAssertNil(model.changeError, name)
      let saved = try Settings.load(at: url)
      XCTAssertTrue(check(saved), name)
      XCTAssertEqual(model.settings, saved, name)
    }
  }

  @MainActor
  func testOnlyChangesThatWriteAreTold() throws {
    let url = try makeFile()
    var told: [Double] = []
    let model = SettingsModel(fileURL: url) {
      told.append((try? Settings.load(at: url))?.idleMinutes ?? -1)
    }
    model.setNumber(\.idleMinutes, from: "8")
    model.setNumber(\.idleMinutes, from: "8")
    XCTAssertEqual(told, [8], "a change the file already has isn't told")
  }

  @MainActor
  func testFieldThatIsNotANumberSavesNothing() throws {
    let (model, url) = try makeModel()
    model.setNumber(\.idleMinutes, from: "ten")
    XCTAssertEqual(model.changeError, "\"ten\" isn't a number")
    XCTAssertEqual(try Settings.load(at: url), Settings.starter)
    model.setNumber(\.idleMinutes, from: "0")
    XCTAssertTrue(model.changeError?.contains("idleMinutes") == true, "\(model.changeError ?? "")")
    model.setNumber(\.idleMinutes, from: "6")
    XCTAssertNil(model.changeError)
  }

  @MainActor
  func testRangeMonthMustBeAMonth() throws {
    let (model, url) = try makeModel()
    model.setTimeframeKind(.range, today: today)
    model.setRange(first: true, from: "2014-13")
    XCTAssertTrue(model.changeError?.contains("2014-13") == true)
    model.setRange(first: false, from: "2025-01")
    XCTAssertTrue(model.changeError?.contains("timeframe.from") == true)
    XCTAssertEqual(
      try Settings.load(at: url).timeframe, .range(from: month(2026, 1), to: today))
  }

  @MainActor
  func testSlideChoicesAreTheSpeedsAndTheFilesOwn() throws {
    let (model, _) = try makeModel()
    XCTAssertEqual(model.slideChoices, [5, 15, 30, 60, 300])
    model.set(\.slideSeconds, to: 45.5)
    XCTAssertEqual(model.slideChoices, [5, 15, 30, 60, 300, 45.5])
    XCTAssertEqual(SettingsModel.describe(slideSeconds: 300), "5 minutes")
    XCTAssertEqual(SettingsModel.describe(slideSeconds: 45.5), "Custom: 45.5 seconds")
  }

  @MainActor
  func testShowsAnEditToTheFile() throws {
    let (model, url) = try makeModel()
    var edited = Settings.starter
    edited.kenBurns = false
    try edited.encoded().write(to: url)
    model.reload()
    XCTAssertEqual(model.settings, edited)
  }

  @MainActor
  func testBrokenFileListsWhatIsMissingAndIsNotWritten() throws {
    let (model, url) = try makeModel()
    var json = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Settings.starter.encoded()) as? [String: Any])
    json["timeframe"] = nil
    let broken = try JSONSerialization.data(withJSONObject: json)
    try broken.write(to: url)
    model.reload()

    XCTAssertTrue(model.isFileBroken)
    XCTAssertTrue(model.fileError?.contains("timeframe") == true)
    XCTAssertEqual(
      model.missingKeys, [Settings.MissingKey(path: "timeframe", value: "{\"kind\":\"all\"}")])
    model.set(\.kenBurns, to: false)
    XCTAssertNotNil(model.changeError)
    XCTAssertEqual(try Data(contentsOf: url), broken)

    try Settings.starter.encoded().write(to: url)
    model.reload()
    XCTAssertFalse(model.isFileBroken)
    XCTAssertEqual(model.missingKeys, [])
    XCTAssertNil(model.changeError)
  }

  @MainActor
  func testRecordedKeyBecomesTheCommandsKey() throws {
    let (model, url) = try makeModel()
    let key = KeySpec(.character("n"), modifiers: [.shift])
    XCTAssertFalse(model.record(key), "not recording")
    model.toggleRecording(.next)
    XCTAssertEqual(model.recording, .next)
    XCTAssertTrue(model.record(key))
    XCTAssertNil(model.recording)
    XCTAssertEqual(try Settings.load(at: url).keys[.next], key)
    XCTAssertEqual(try Settings.load(at: url).keys[.previous], Command.previous.defaultKey)
  }

  @MainActor
  func testEscapeCancelsRecording() throws {
    let (model, url) = try makeModel()
    model.toggleRecording(.info)
    XCTAssertTrue(model.record(KeySpec(.named(.escape))))
    XCTAssertNil(model.recording)
    XCTAssertEqual(try Settings.load(at: url), Settings.starter)
    // With a modifier, Esc is a key like any other.
    model.toggleRecording(.info)
    XCTAssertTrue(model.record(KeySpec(.named(.escape), modifiers: .shift)))
    XCTAssertEqual(
      try Settings.load(at: url).keys[.info], KeySpec(.named(.escape), modifiers: .shift))
  }

  @MainActor
  func testKeyWithNoNameOrAnotherCommandsKeyIsRefused() throws {
    let (model, url) = try makeModel()
    model.toggleRecording(.info)
    XCTAssertTrue(model.record(nil))
    XCTAssertEqual(model.recording, .info)
    XCTAssertNotNil(model.refusal)

    XCTAssertTrue(model.record(Command.next.defaultKey))
    XCTAssertEqual(model.recording, .info, "keeps listening")
    XCTAssertTrue(
      model.refusal?.contains("keys.next and keys.info are both \"right\"") == true,
      model.refusal ?? "")
    XCTAssertEqual(try Settings.load(at: url), Settings.starter)

    model.toggleRecording(.info)
    XCTAssertNil(model.recording)
    XCTAssertNil(model.refusal)
  }

  @MainActor
  func testRestoreDefaultKeys() throws {
    let (model, url) = try makeModel()
    model.toggleRecording(.pause)
    _ = model.record(KeySpec(.character("p")))
    model.restoreDefaultKeys()
    XCTAssertEqual(try Settings.load(at: url).keys, Settings.starter.keys)
  }

  func testNumberText() {
    XCTAssertEqual(SettingsModel.text(5), "5")
    XCTAssertEqual(SettingsModel.text(1.5), "1.5")
    XCTAssertEqual(SettingsModel.text(0.2), "0.2")
  }

  // MARK: Helpers

  private let today = CaptureMonth(year: 2026, month: 11)

  private func month(_ year: Int, _ month: Int) -> CaptureMonth {
    CaptureMonth(year: year, month: month)
  }

  private func makeFile() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("config.json")
    try Settings.starter.encoded().write(to: url)
    return url
  }

  @MainActor
  private func makeModel() throws -> (SettingsModel, URL) {
    let url = try makeFile()
    return (SettingsModel(fileURL: url) {}, url)
  }
}
