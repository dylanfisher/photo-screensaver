import XCTest

@testable import Core

final class PhotoDetailsTests: XCTestCase {
  private var library: LibraryFixture!

  override func setUpWithError() throws { library = try LibraryFixture() }
  override func tearDownWithError() throws { try library.remove() }

  private struct Offline: Error {}

  /// Answers with `place`, or throws `Offline` while `offline` is set, and counts the calls.
  private actor FakeGeocoder: Geocoder {
    let place: Place?
    private(set) var calls = 0
    var offline = false

    init(_ place: Place?) { self.place = place }

    func setOffline(_ offline: Bool) { self.offline = offline }

    func place(latitude: Double, longitude: Double) async throws -> Place? {
      calls += 1
      if offline { throw Offline() }
      return place
    }
  }

  private func details(_ geocoder: FakeGeocoder, lookupDelay: Double = 0) throws -> PhotoDetails {
    _ = try library.open()
    return try PhotoDetails(
      databaseURL: library.database, root: library.root, geocoder: geocoder,
      lookupDelay: lookupDelay)
  }

  private let tokyo = Place(subLocality: "Shibuya", locality: "Tokyo", country: "Japan")

  func testLooksUpEachPlaceOnce() async throws {
    let geocoder = FakeGeocoder(tokyo)
    let details = try details(geocoder)
    let cachedBefore = try await details.cachedPlace(latitude: 35.6595, longitude: 139.7005)
    XCTAssertNil(cachedBefore)
    let first = try await details.lookUpPlace(latitude: 35.6595, longitude: 139.7005)
    XCTAssertEqual(first, .named("Shibuya, Tokyo, Japan"))
    // A few hundred meters away is the same cell.
    let nearby = try await details.lookUpPlace(latitude: 35.6582, longitude: 139.7021)
    XCTAssertEqual(nearby, first)
    let calls = await geocoder.calls
    XCTAssertEqual(calls, 1)
    let cached = try await details.cachedPlace(latitude: 35.6582, longitude: 139.7021)
    XCTAssertEqual(cached, first)
  }

  func testAPlaceFarEnoughAwayIsLookedUpAgain() async throws {
    let geocoder = FakeGeocoder(tokyo)
    let details = try details(geocoder)
    _ = try await details.lookUpPlace(latitude: 35.6595, longitude: 139.7005)
    _ = try await details.lookUpPlace(latitude: 35.6795, longitude: 139.7005)
    let calls = await geocoder.calls
    XCTAssertEqual(calls, 2)
  }

  func testAFailedLookupIsTriedAgain() async throws {
    let geocoder = FakeGeocoder(tokyo)
    await geocoder.setOffline(true)
    let details = try details(geocoder)
    do {
      _ = try await details.lookUpPlace(latitude: 35.6595, longitude: 139.7005)
      XCTFail("expected an error")
    } catch is Offline {}
    let cached = try await details.cachedPlace(latitude: 35.6595, longitude: 139.7005)
    XCTAssertNil(cached)
    await geocoder.setOffline(false)
    let place = try await details.lookUpPlace(latitude: 35.6595, longitude: 139.7005)
    XCTAssertEqual(place, .named("Shibuya, Tokyo, Japan"))
    let calls = await geocoder.calls
    XCTAssertEqual(calls, 2)
  }

  func testALookupCancelledWhileWaitingAsksNothing() async throws {
    let geocoder = FakeGeocoder(tokyo)
    let details = try details(geocoder, lookupDelay: 0.5)
    let lookup = Task { try await details.lookUpPlace(latitude: 35.6595, longitude: 139.7005) }
    try await Task.sleep(nanoseconds: 100_000_000)
    lookup.cancel()
    do {
      _ = try await lookup.value
      XCTFail("expected a cancellation")
    } catch is CancellationError {}
    let calls = await geocoder.calls
    XCTAssertEqual(calls, 0)
  }

  func testACachedPlaceDoesNotWait() async throws {
    let geocoder = FakeGeocoder(tokyo)
    _ = try await details(geocoder).lookUpPlace(latitude: 35.6595, longitude: 139.7005)
    let waiting = try details(geocoder, lookupDelay: 60)
    let started = Date()
    let place = try await waiting.lookUpPlace(latitude: 35.6595, longitude: 139.7005)
    XCTAssertEqual(place, .named("Shibuya, Tokyo, Japan"))
    XCTAssertLessThan(Date().timeIntervalSince(started), 5)
  }

  func testNoPlaceThereIsRememberedToo() async throws {
    let geocoder = FakeGeocoder(nil)
    let details = try details(geocoder)
    let first = try await details.lookUpPlace(latitude: 0, longitude: -140)
    XCTAssertEqual(first, .unnamed)
    let second = try await details.lookUpPlace(latitude: 0, longitude: -140)
    XCTAssertEqual(second, .unnamed)
    let calls = await geocoder.calls
    XCTAssertEqual(calls, 1)
  }

  func testPlacesOutlastAnotherLibraryFolder() async throws {
    let geocoder = FakeGeocoder(tokyo)
    _ = try await details(geocoder).lookUpPlace(latitude: 35.6595, longitude: 139.7005)
    try PhotoLibrary(at: library.database).use(root: library.base)
    let reopened = try PhotoDetails(
      databaseURL: library.database, root: library.base, geocoder: geocoder, lookupDelay: 0)
    let cached = try await reopened.cachedPlace(latitude: 35.6595, longitude: 139.7005)
    XCTAssertEqual(cached, .named("Shibuya, Tokyo, Japan"))
  }

  func testReadsAPhotoTheScanHasNotReadWithoutStoringIt() async throws {
    let url = try library.jpeg("Trip/a.jpg", properties: LibraryFixture.cameraProperties)
    let details = try details(FakeGeocoder(nil))
    let database = try PhotoLibrary(at: library.database)
    let size = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    try database.insert(
      [WalkedFile(path: "Trip/a.jpg", size: size, mtime: 0)],
      root: PhotoLibrary.path(of: library.root))
    let id = try XCTUnwrap(database.photoIDs().first)

    let photo = try await details.photo(id)
    let unread = try XCTUnwrap(photo)
    XCTAssertNil(unread.metadata)
    let metadata = try await details.readMetadata(of: unread)
    XCTAssertEqual(metadata.model, "iPhone 12")
    XCTAssertNil(try database.photo(id)?.metadata, "the scan stores details, not the panel")
  }
}
