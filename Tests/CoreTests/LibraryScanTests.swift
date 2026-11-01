import Darwin
import XCTest

@testable import Core

final class LibraryScanTests: XCTestCase {
  private var library: LibraryFixture!

  override func setUpWithError() throws { library = try LibraryFixture() }
  override func tearDownWithError() throws { try library.remove() }

  func testFindsPhotosRecursivelyAsRelativePaths() throws {
    try library.jpeg("Astoria/one.jpg")
    try library.jpeg("Astoria/Rooftop/two.JPG")
    try library.jpeg("three.jpeg")
    let summary = try library.scan()
    XCTAssertEqual(summary.found, 3)
    XCTAssertEqual(
      try library.paths(), ["Astoria/Rooftop/two.JPG", "Astoria/one.jpg", "three.jpeg"])
  }

  func testSkipsNonPhotosHiddenFilesAndNASFolders() throws {
    try library.jpeg("keep.jpg")
    try library.text("notes.txt")
    try library.text(".download_manifest.json")
    try library.jpeg(".hidden.jpg")
    try library.jpeg("Album/@eaDir/keep.jpg/SYNOPHOTO_THUMB_XL.jpg")
    try library.jpeg("#recycle/deleted.jpg")
    try library.scan()
    XCTAssertEqual(try library.paths(), ["keep.jpg"])
  }

  func testMissingLibraryThrows() throws {
    _ = try library.open()
    let missing = library.root.appendingPathComponent("nope")
    XCTAssertThrowsError(try LibraryScan(databaseURL: library.database, root: missing).run())
  }

  func testADatabaseSetUpForAnotherFolderThrows() throws {
    try library.jpeg("a.jpg")
    let other = try PhotoLibrary(at: library.database)
    try other.use(root: URL(fileURLWithPath: "/elsewhere"))
    XCTAssertThrowsError(try LibraryScan(databaseURL: library.database, root: library.root).run())
  }

  func testReadsDetailsOnlyOfNewAndChangedFiles() throws {
    try library.jpeg("a.jpg", properties: LibraryFixture.taken("2020:01:01 10:00:00"))
    try library.jpeg("b.jpg")
    XCTAssertEqual(try library.scan().read, 2)
    XCTAssertEqual(try library.scan().read, 0)

    try library.jpeg("a.jpg", width: 60, properties: LibraryFixture.taken("2022:02:02 10:00:00"))
    try library.jpeg("c.jpg")
    XCTAssertEqual(try library.scan().read, 2)
    let photos = try records()
    XCTAssertEqual(photos["a.jpg"]?.metadata?.takenAt, "2022-02-02 10:00:00")
    XCTAssertEqual(photos["a.jpg"]?.metadata?.width, 60)
    XCTAssertEqual(photos.count, 3)
  }

  func testRemovesFilesThatAreGoneAfterACompleteWalk() throws {
    try library.jpeg("a.jpg")
    let gone = try library.jpeg("Album/b.jpg")
    try library.jpeg("Album/c.jpg")
    let goneFolder = try library.jpeg("Old/d.jpg").deletingLastPathComponent()
    try library.scan()
    try FileManager.default.removeItem(at: gone)
    try FileManager.default.removeItem(at: goneFolder)
    XCTAssertEqual(try library.scan().removed, 2)
    XCTAssertEqual(try library.paths(), ["Album/c.jpg", "a.jpg"])
  }

  func testKeepsPhotosUnderAFolderThatCanNotBeListed() throws {
    try XCTSkipIf(geteuid() == 0, "root lists a folder without permissions")
    try library.jpeg("a.jpg")
    try library.jpeg("Locked/b.jpg")
    try library.jpeg("Locked/Inner/c.jpg")
    try library.scan()
    let locked = library.root.appendingPathComponent("Locked")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }
    let summary = try library.scan()
    XCTAssertEqual(summary.unreadable, 1)
    XCTAssertEqual(summary.removed, 0)
    XCTAssertEqual(try library.paths(), ["Locked/Inner/c.jpg", "Locked/b.jpg", "a.jpg"])
  }

  func testKeepsPhotosWhenTheFolderListsNothing() throws {
    let photo = try library.jpeg("a.jpg")
    try library.scan()
    try FileManager.default.removeItem(at: photo)
    let summary = try library.scan()
    XCTAssertTrue(summary.listedNothing)
    XCTAssertEqual(summary.removed, 0)
    XCTAssertEqual(try library.paths(), ["a.jpg"])
  }

  func testKeepsPhotosUnderAFolderThatListsNothing() throws {
    try library.jpeg("a.jpg")
    let album = try library.jpeg("Album/b.jpg").deletingLastPathComponent()
    try library.jpeg("Album/Inner/c.jpg")
    try library.scan()
    // As when an SMB glitch lists the folder as empty.
    try FileManager.default.removeItem(at: album)
    try FileManager.default.createDirectory(at: album, withIntermediateDirectories: false)
    let summary = try library.scan()
    XCTAssertEqual(summary.unreadable, 1)
    XCTAssertEqual(summary.removed, 0)
    XCTAssertEqual(try library.paths(), ["Album/Inner/c.jpg", "Album/b.jpg", "a.jpg"])
  }

  func testAnEmptyFolderWithNoPhotosIsNotAProblem() throws {
    try library.jpeg("a.jpg")
    try FileManager.default.createDirectory(
      at: library.root.appendingPathComponent("Empty"), withIntermediateDirectories: false)
    XCTAssertEqual(try library.scan().unreadable, 0)
  }

  func testFindsTheFolderAboveAPath() {
    let folders: Set<String> = ["A", "B/C"]
    XCTAssertEqual(LibraryScan.folder(containing: "A", in: folders), "A")
    XCTAssertEqual(LibraryScan.folder(containing: "A/x.jpg", in: folders), "A")
    XCTAssertEqual(LibraryScan.folder(containing: "B/C/D/x.jpg", in: folders), "B/C")
    XCTAssertNil(LibraryScan.folder(containing: "AB/x.jpg", in: folders))
    XCTAssertNil(LibraryScan.folder(containing: "B/x.jpg", in: folders))
  }

  func testKeepsEveryPhotoWhenTheFolderMovesToAnotherDevice() throws {
    try library.jpeg("a.jpg")
    let gone = try library.jpeg("b.jpg")
    try library.scan()
    try FileManager.default.removeItem(at: gone)
    let scan = LibraryScan(databaseURL: library.database, root: library.root)
    // The first stat is at the start of the scan, the next when the walk finishes.
    var stats: dev_t = 0
    scan.deviceOf = { _ in
      stats += 1
      return stats
    }
    XCTAssertThrowsError(try scan.run()) { error in
      XCTAssertTrue("\(error)".contains("went away"), "\(error)")
    }
    XCTAssertEqual(try library.paths(), ["a.jpg", "b.jpg"])
  }

  func testAFileThatCanNotBeReadStaysUnreadAndShown() throws {
    try XCTSkipIf(geteuid() == 0, "root reads a file without permissions")
    try library.jpeg("a.jpg")
    let locked = try library.jpeg("b.jpg")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    let first = try library.scan()
    XCTAssertEqual([first.read, first.failed], [1, 1])
    XCTAssertNil(try records()["b.jpg"]?.metadata)
    XCTAssertEqual(try library.paths(), ["a.jpg", "b.jpg"])
    // The next scan tries it again.
    XCTAssertEqual(try library.scan().failed, 1)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
    XCTAssertEqual(try library.scan().read, 1)
    XCTAssertNotNil(try records()["b.jpg"]?.metadata)
  }

  func testACancelledScanRemovesNothing() throws {
    try library.jpeg("a.jpg")
    let gone = try library.jpeg("b.jpg")
    try library.jpeg("Album/c.jpg")
    try library.scan()
    try FileManager.default.removeItem(at: gone)
    let scan = LibraryScan(databaseURL: library.database, root: library.root)
    // Cancelled after the walk has listed the library folder but before it can finish.
    scan.didList = { [weak scan] _ in scan?.cancel() }
    let summary = try scan.run()
    XCTAssertTrue(summary.cancelled)
    XCTAssertEqual(summary.removed, 0)
    XCTAssertEqual(try library.paths(), ["Album/c.jpg", "a.jpg", "b.jpg"])
  }

  func testAFileWithNoImageIsReadOnceAndNotShown() throws {
    try library.jpeg("good.jpg")
    try library.text("broken.jpg")
    XCTAssertEqual(try library.scan().read, 2)
    XCTAssertEqual(try library.paths(), ["good.jpg"])
    XCTAssertEqual(try library.scan().read, 0)
  }

  func testPublishesProgressEndingWithEveryPhotoRead() async throws {
    for name in ["a", "b", "c"] { try library.jpeg("Album/\(name).jpg") }
    _ = try library.open()
    var continuation: AsyncStream<LibraryScan.Progress>.Continuation?
    let stream = AsyncStream<LibraryScan.Progress> { continuation = $0 }
    let scan = LibraryScan(
      databaseURL: library.database, root: library.root, progress: continuation)
    _ = try scan.run()
    var last: LibraryScan.Progress?
    for await progress in stream { last = progress }
    let progress = try XCTUnwrap(last)
    XCTAssertEqual(progress.found, 3)
    XCTAssertTrue(progress.walkFinished)
    XCTAssertEqual([progress.photos, progress.unread], [3, 0])
  }

  func testManyFilesAcrossFoldersAreAllRead() throws {
    for folder in 0..<8 {
      for file in 0..<40 {
        try library.jpeg("F\(folder)/S\(folder % 3)/\(file).jpg", width: 4, height: 4)
      }
    }
    let summary = try library.scan()
    XCTAssertEqual(summary.read, 320)
    XCTAssertEqual(try PhotoLibrary(at: library.database).count(), 320)
    XCTAssertEqual(try records().values.filter { $0.metadata == nil }.count, 0)
  }

  private func records() throws -> [String: PhotoRecord] {
    let database = try PhotoLibrary(at: library.database)
    var records: [String: PhotoRecord] = [:]
    for id in try database.photoIDs() {
      if let record = try database.photo(id) { records[record.path] = record }
    }
    return records
  }
}
