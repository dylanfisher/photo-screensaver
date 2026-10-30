import Core
import XCTest

final class PhotoIndexTests: XCTestCase {
  private var library: LibraryFixture!

  override func setUpWithError() throws { library = try LibraryFixture() }
  override func tearDownWithError() throws { try library.remove() }

  func testFindsPhotosRecursivelyAsRelativePaths() throws {
    try library.jpeg("Astoria/one.jpg")
    try library.jpeg("Astoria/Rooftop/two.JPG")
    try library.jpeg("three.jpeg")
    let index = try PhotoIndex.scan(library.root)
    XCTAssertEqual(index.paths, ["Astoria/Rooftop/two.JPG", "Astoria/one.jpg", "three.jpeg"])
  }

  func testSkipsNonPhotosHiddenFilesAndNASFolders() throws {
    try library.jpeg("keep.jpg")
    try library.text("notes.txt")
    try library.text(".download_manifest.json")
    try library.jpeg(".hidden.jpg")
    try library.jpeg("Album/@eaDir/keep.jpg/SYNOPHOTO_THUMB_XL.jpg")
    try library.jpeg("#recycle/deleted.jpg")
    XCTAssertEqual(try PhotoIndex.scan(library.root).paths, ["keep.jpg"])
  }

  func testMissingLibraryThrows() {
    XCTAssertThrowsError(try PhotoIndex.scan(library.root.appendingPathComponent("nope")))
  }

  func testCacheRoundTripsOnlyForTheSameRoot() throws {
    try library.jpeg("a.jpg")
    let cache = library.root.appendingPathComponent("cache/index.json")
    let index = try PhotoIndex.scan(library.root)
    try index.save(to: cache)

    XCTAssertEqual(try PhotoIndex.cached(for: library.root, at: cache), index)
    XCTAssertNil(try PhotoIndex.cached(for: URL(fileURLWithPath: "/elsewhere"), at: cache))
  }

  func testURLForPathPointsInsideRoot() throws {
    let url = try library.jpeg("Album/a b.jpg")
    let index = try PhotoIndex.scan(library.root)
    XCTAssertEqual(index.url(for: "Album/a b.jpg").standardizedFileURL, url.standardizedFileURL)
  }
}
