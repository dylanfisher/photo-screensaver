import Core
import Primitives
import Settings
import XCTest

final class PhotoLibraryTests: XCTestCase {
  private var library: LibraryFixture!

  override func setUpWithError() throws { library = try LibraryFixture() }
  override func tearDownWithError() throws { try library.remove() }

  func testKeepsPhotosWhenTheSchemaMatches() throws {
    try library.jpeg("a.jpg")
    try library.scan()
    XCTAssertEqual(try PhotoLibrary(at: library.database).count(), 1)
  }

  func testRebuildsWhenTheStoredSchemaSQLDiffers() throws {
    try library.jpeg("a.jpg")
    try library.scan()
    let raw = try SQLiteDatabase(at: library.database)
    try raw.execute("UPDATE schema_identity SET sql = 'CREATE TABLE photos (path TEXT)'")
    try raw.execute("CREATE TABLE leftover (x)")

    let reopened = try PhotoLibrary(at: library.database)
    XCTAssertEqual(try reopened.count(), 0)
    XCTAssertNil(try reopened.root())
    let tables = try raw.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").map {
      try $0.text(0)
    }
    XCTAssertFalse(tables.contains("leftover"))
    // The next scan refills it.
    try library.scan()
    XCTAssertEqual(try reopened.count(), 1)
  }

  func testAnotherLibraryFolderDiscardsThePhotos() throws {
    try library.jpeg("a.jpg")
    try library.scan()
    let database = try PhotoLibrary(at: library.database)
    try database.use(root: library.root)
    XCTAssertEqual(try database.count(), 1)
    try database.use(root: URL(fileURLWithPath: "/elsewhere"))
    XCTAssertEqual(try database.count(), 0)
    XCTAssertEqual(try database.root(), "/elsewhere")
  }

  func testStoresEveryDetailRead() throws {
    try library.jpeg("a.jpg", width: 60, height: 40, properties: LibraryFixture.cameraProperties)
    try library.scan()
    let database = try PhotoLibrary(at: library.database)
    let id = try XCTUnwrap(database.photoIDs().first)
    let photo = try XCTUnwrap(database.photo(id))
    XCTAssertEqual(photo.path, "a.jpg")
    XCTAssertEqual(
      photo.metadata, try PhotoMetadata.read(at: library.root.appendingPathComponent("a.jpg")))
    XCTAssertEqual(photo.metadata?.model, "iPhone 12")
  }

  func testTimeframeExcludesUndatedPhotos() throws {
    let dates = [
      "2019-12.jpg": "2019:12:31 23:59:59", "2020-01.jpg": "2020:01:01 00:00:00",
      "2020-06.jpg": "2020:06:15 12:00:00", "2020-12.jpg": "2020:12:31 23:59:59",
      "2021-01.jpg": "2021:01:01 00:00:00",
    ]
    for (name, date) in dates { try library.jpeg(name, properties: LibraryFixture.taken(date)) }
    try library.jpeg("undated.jpg")
    try library.scan()
    let database = try PhotoLibrary(at: library.database)

    let all = try database.photoIDs()
    XCTAssertEqual(all.count, 6)
    let in2020 = try database.photoIDs(
      takenIn: CaptureMonth(year: 2020, month: 1)...CaptureMonth(year: 2020, month: 12))
    XCTAssertEqual(
      try in2020.compactMap { try database.photo($0)?.path }.sorted(),
      ["2020-01.jpg", "2020-06.jpg", "2020-12.jpg"])
    let june = try database.photoIDs(
      takenIn: CaptureMonth(year: 2020, month: 6)...CaptureMonth(year: 2020, month: 6))
    XCTAssertEqual(try june.compactMap { try database.photo($0)?.path }, ["2020-06.jpg"])
  }

  func testCountsPhotosPerYear() throws {
    try library.jpeg("a.jpg", properties: LibraryFixture.taken("2019:05:01 10:00:00"))
    try library.jpeg("b.jpg", properties: LibraryFixture.taken("2020:05:01 10:00:00"))
    try library.jpeg("c.jpg", properties: LibraryFixture.taken("2020:09:01 10:00:00"))
    try library.jpeg("undated.jpg")
    try library.scan()
    XCTAssertEqual(try PhotoLibrary(at: library.database).yearCounts(), [2019: 1, 2020: 2])
  }

  func testARemovedPhotosIDIsNotUsedAgain() throws {
    try library.jpeg("a.jpg")
    try library.scan()
    let first = try library.open().photoIDs()
    let gone = try library.jpeg("b.jpg")
    try library.scan()
    let removedID = try XCTUnwrap(Set(try library.open().photoIDs()).subtracting(first).first)
    try FileManager.default.removeItem(at: gone)
    try library.scan()
    try library.jpeg("c.jpg")
    try library.scan()
    let database = try library.open()
    XCTAssertNil(try database.photo(removedID))
    XCTAssertEqual(
      try database.photoIDs().compactMap { try database.photo($0)?.path }.sorted(),
      ["a.jpg", "c.jpg"])
  }

  func testAMissingIDHasNoPhoto() throws {
    XCTAssertNil(try library.open().photo(42))
  }
}
