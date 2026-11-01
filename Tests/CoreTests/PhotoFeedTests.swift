import Settings
import XCTest

@testable import Core

final class PhotoFeedTests: XCTestCase {
  private var library: LibraryFixture!

  override func setUpWithError() throws { library = try LibraryFixture() }
  override func tearDownWithError() throws { try library.remove() }

  func testShowsEveryPhotoBeforeRepeating() async throws {
    for name in ["a", "b", "c", "d"] { try library.jpeg("\(name).jpg") }
    let feed = try makeFeed()
    var seen: Set<String> = []
    for _ in 0..<4 { seen.insert(try await feed.next().url.lastPathComponent) }
    XCTAssertEqual(seen, ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
  }

  func testLandscapeOnlySkipsPortraits() async throws {
    try library.jpeg("wide.jpg", width: 30, height: 20)
    try library.jpeg("tall.jpg", width: 20, height: 30)
    var settings = Settings.starter
    settings.orientation = .landscape
    let feed = try makeFeed(settings)
    for _ in 0..<6 {
      let photo = try await feed.next()
      XCTAssertEqual(photo.url.lastPathComponent, "wide.jpg")
    }
  }

  func testDecodesAtTwiceScreenSizeCappedAtOriginal() async throws {
    try library.jpeg("big.jpg", width: 400, height: 200)
    // 100×50 screen: fill shows the photo 100 wide, so decode 200 wide.
    var settings = Settings.starter
    settings.kenBurns = false
    let feed = try makeFeed(settings, screen: CGSize(width: 100, height: 50))
    let photo = try await feed.next()
    XCTAssertEqual(photo.size, CGSize(width: 200, height: 100))
  }

  func testKenBurnsDecodesForTheDeepestZoom() async throws {
    try library.jpeg("big.jpg", width: 400, height: 200)
    // Shown 100 wide, zoomed up to 1.2× to 120, so decode 240 wide.
    var settings = Settings.starter
    settings.kenBurns = true
    let feed = try makeFeed(settings, screen: CGSize(width: 100, height: 50))
    let photo = try await feed.next()
    XCTAssertEqual(photo.size, CGSize(width: 240, height: 120))
  }

  func testSkipsUnreadableFiles() async throws {
    try library.jpeg("good.jpg")
    try library.text("broken.jpg")
    let feed = try makeFeed()
    for _ in 0..<4 {
      let photo = try await feed.next()
      XCTAssertEqual(photo.url.lastPathComponent, "good.jpg")
    }
  }

  func testAllFilesUnreadableThrows() async throws {
    for i in 0..<3 { try library.jpeg("broken\(i).jpg") }
    let feed = try makeFeed()
    // Broken after the scan, as when the share stops serving them.
    for i in 0..<3 { try library.text("broken\(i).jpg") }
    do {
      _ = try await feed.next()
      XCTFail("expected an error")
    } catch let error as FeedError {
      XCTAssertTrue(error.description.contains("in a row"), error.description)
    }
  }

  func testEmptyLibraryThrows() async throws {
    let feed = try makeFeed()
    do {
      _ = try await feed.next()
      XCTFail("expected an error")
    } catch let error as FeedError {
      XCTAssertTrue(error.description.contains("no photos"), error.description)
    }
  }

  func testShowsOnlyPhotosInTheTimeframe() async throws {
    try library.jpeg("2014.jpg", properties: LibraryFixture.taken("2014:05:01 10:00:00"))
    try library.jpeg("2015.jpg", properties: LibraryFixture.taken("2015:05:01 10:00:00"))
    try library.jpeg("undated.jpg")
    var settings = Settings.starter
    settings.timeframe = .year(2014)
    let feed = try makeFeed(settings)
    for _ in 0..<4 {
      let photo = try await feed.next()
      XCTAssertEqual(photo.url.lastPathComponent, "2014.jpg")
    }
  }

  func testATimeframeWithNoPhotosSaysSo() async throws {
    try library.jpeg("2014.jpg", properties: LibraryFixture.taken("2014:05:01 10:00:00"))
    var settings = Settings.starter
    settings.timeframe = .year(2020)
    let feed = try makeFeed(settings)
    do {
      _ = try await feed.next()
      XCTFail("expected an error")
    } catch let error as FeedError {
      XCTAssertTrue(error.description.contains("no photos taken in \"2020\""), error.description)
    }
  }

  func testALoadReadsTheIDsOnceHoweverManyPassesItTakes() async throws {
    // Neither is landscape, so the load goes through both hundreds of times before giving up.
    try library.jpeg("a.jpg", width: 20, height: 30)
    try library.jpeg("b.jpg", width: 20, height: 30)
    var settings = Settings.starter
    settings.orientation = .landscape
    let feed = try makeFeed(settings)
    do {
      _ = try await feed.next()
      XCTFail("expected an error")
    } catch let error as FeedError {
      XCTAssertTrue(error.description.contains("no landscape photos"), error.description)
    }
    let reads = await feed.idReads
    XCTAssertEqual(reads, 1)
  }

  func testDropWakesAWaitingCallerWithCancellation() async throws {
    try library.jpeg("a.jpg", width: 3000, height: 2000)
    let feed = try makeFeed()
    let waiting = Task { try await feed.next() }
    await feed.drop()
    do {
      _ = try await waiting.value
    } catch is CancellationError {
      return
    }
    // The decode may have finished before the drop; that's fine too.
  }

  func testCancelledCallerDoesNotTakeThePhoto() async throws {
    try library.jpeg("only.jpg", width: 3000, height: 2000)
    var settings = Settings.starter
    settings.preloadCount = 1
    let feed = try makeFeed(settings)
    let cancelled = Task { try await feed.next() }
    cancelled.cancel()
    let photo = try await feed.next()
    XCTAssertEqual(photo.url.lastPathComponent, "only.jpg")
    let result = await cancelled.result
    XCTAssertThrowsError(try result.get())
  }

  func testWorksAgainAfterDrop() async throws {
    try library.jpeg("a.jpg")
    let feed = try makeFeed()
    _ = try await feed.next()
    await feed.drop()
    let photo = try await feed.next()
    XCTAssertEqual(photo.url.lastPathComponent, "a.jpg")
  }

  func testReloadPicksUpWhatAScanAdded() async throws {
    try library.jpeg("a.jpg")
    let feed = try makeFeed()
    _ = try await feed.next()
    try library.jpeg("b.jpg")
    try library.scan()
    await feed.drop()
    await feed.reload()
    var seen: Set<String> = []
    for _ in 0..<2 { seen.insert(try await feed.next().url.lastPathComponent) }
    XCTAssertEqual(seen, ["a.jpg", "b.jpg"])
  }

  func testEachPassPicksUpWhatAScanAddedWithoutAReload() async throws {
    try library.jpeg("a.jpg")
    var settings = Settings.starter
    settings.preloadCount = 1
    let feed = try makeFeed(settings)
    _ = try await feed.next()
    try library.jpeg("b.jpg")
    try library.scan()
    // At most one photo preloaded and one pass of a.jpg alone before the IDs are read again.
    var seen: Set<String> = []
    for _ in 0..<4 { seen.insert(try await feed.next().url.lastPathComponent) }
    XCTAssertTrue(seen.contains("b.jpg"), "\(seen)")
  }

  func testRetriesAfterAFailure() async throws {
    let feed = try makeFeed()
    for _ in 0..<2 {
      do {
        _ = try await feed.next()
        XCTFail("expected an error")
      } catch let error as FeedError {
        XCTAssertTrue(error.description.contains("no photos"), error.description)
      }
    }
  }

  func testRevisitDecodesAPhotoShownBefore() async throws {
    try library.jpeg("a.jpg")
    let feed = try makeFeed()
    let shown = try await feed.next()
    let again = try await feed.photo(shown.id)
    XCTAssertEqual(again.id, shown.id)
    XCTAssertEqual(again.url, shown.url)
    XCTAssertEqual(again.size, shown.size)
  }

  func testRevisitIgnoresOrientation() async throws {
    try library.jpeg("tall.jpg", width: 20, height: 30)
    let first = try makeFeed()
    let tall = try await first.next()
    var settings = Settings.starter
    settings.orientation = .landscape
    let feed = try makeFeed(settings)
    let photo = try await feed.photo(tall.id)
    XCTAssertEqual(photo.url.lastPathComponent, "tall.jpg")
  }

  func testRevisitOfARemovedPhotoThrows() async throws {
    try library.jpeg("a.jpg")
    let feed = try makeFeed()
    let shown = try await feed.next()
    do {
      _ = try await feed.photo(shown.id + 1)
      XCTFail("expected an error")
    } catch let error as FeedError {
      XCTAssertTrue(error.description.contains("no longer"), error.description)
    }
  }

  func testPreloadsCarryOnAfterARevisit() async throws {
    for name in ["a", "b"] { try library.jpeg("\(name).jpg") }
    let feed = try makeFeed()
    let first = try await feed.next()
    _ = try await feed.photo(first.id)
    let second = try await feed.next()
    XCTAssertNotEqual(second.id, first.id)
  }

  func testARevisitInterruptedByADropDoesNotPreload() async throws {
    for name in ["a", "b"] { try library.jpeg("\(name).jpg", width: 3000, height: 2000) }
    let feed = try makeFeed()
    let shown = try await feed.next()
    // next() started a preload, which the revisit waits for.
    let revisit = Task { try await feed.photo(shown.id) }
    while await feed.revisits == 0 { await Task.yield() }
    await feed.drop()
    _ = try await revisit.value
    let loading = await feed.loader != nil
    XCTAssertFalse(loading)
  }

  func testAPhotoPutBackIsHandedOutNext() async throws {
    for name in ["a", "b", "c"] { try library.jpeg("\(name).jpg") }
    let feed = try makeFeed()
    let unseen = try await feed.next()
    await feed.putBack(unseen)
    let next = try await feed.next()
    XCTAssertEqual(next.id, unseen.id)
  }

  private func makeFeed(
    _ settings: Settings = .starter, screen: CGSize = CGSize(width: 2560, height: 1600)
  ) throws -> PhotoFeed {
    try library.scan()
    return try PhotoFeed(
      databaseURL: library.database, root: library.root, settings: settings, screenPixels: screen)
  }
}
