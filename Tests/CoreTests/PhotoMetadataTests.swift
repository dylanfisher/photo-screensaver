import Core
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class PhotoMetadataTests: XCTestCase {
  private var library: LibraryFixture!

  override func setUpWithError() throws { library = try LibraryFixture() }
  override func tearDownWithError() throws { try library.remove() }

  func testReadsCaptureDateCameraAndLocation() throws {
    let url = try library.jpeg(
      "a.jpg", width: 60, height: 40, properties: LibraryFixture.cameraProperties)
    let metadata = try PhotoMetadata.read(at: url)
    XCTAssertEqual(metadata.width, 60)
    XCTAssertEqual(metadata.height, 40)
    XCTAssertEqual(metadata.takenAt, "2021-07-04 18:30:00")
    XCTAssertEqual(metadata.takenOffset, "-04:00")
    XCTAssertEqual(metadata.make, "Apple")
    XCTAssertEqual(metadata.model, "iPhone 12")
    XCTAssertEqual(metadata.lens, "iPhone 12 back camera 4.2mm f/1.6")
    XCTAssertEqual(metadata.fNumber, 1.6)
    XCTAssertEqual(metadata.exposure, 0.004)
    XCTAssertEqual(metadata.iso, 32)
    XCTAssertEqual(metadata.focalLength, 4.2)
    XCTAssertEqual(metadata.focalLength35mm, 26)
    XCTAssertEqual(try XCTUnwrap(metadata.latitude), 40.7484, accuracy: 1e-4)
    XCTAssertEqual(try XCTUnwrap(metadata.longitude), -73.9857, accuracy: 1e-4)
    XCTAssertEqual(try XCTUnwrap(metadata.altitude), 12.5, accuracy: 1e-3)
  }

  func testSizeIsAsDisplayedAfterRotation() throws {
    let url = try library.jpeg(
      "a.jpg", width: 60, height: 40, properties: [kCGImagePropertyOrientation: 6])
    let metadata = try PhotoMetadata.read(at: url)
    XCTAssertEqual([metadata.width, metadata.height], [40, 60])
  }

  func testAPhotoWithoutEXIFHasOnlyItsSize() throws {
    let metadata = try PhotoMetadata.read(at: library.jpeg("a.jpg"))
    XCTAssertEqual(metadata.width, 30)
    XCTAssertNil(metadata.takenAt)
    XCTAssertNil(metadata.model)
    XCTAssertNil(metadata.latitude)
  }

  func testAnUnsetCameraClockIsNoDate() throws {
    let url = try library.jpeg("a.jpg", properties: LibraryFixture.taken("0000:00:00 00:00:00"))
    XCTAssertNil(try PhotoMetadata.read(at: url).takenAt)
  }

  func testReadsTheRestWhenThePrefixHasNoImageSize() throws {
    let url = try library.jpeg("a.jpg", properties: LibraryFixture.cameraProperties)
    let metadata = try PhotoMetadata.read(at: url, prefixBytes: 64)
    XCTAssertEqual(metadata.takenAt, "2021-07-04 18:30:00")
    XCTAssertEqual(metadata.width, 30)
  }

  func testReadsTheRestOfAFormatThatCanKeepEXIFAnywhere() throws {
    let url = try library.image("a.png", type: .png, width: 300, height: 200)
    let metadata = try PhotoMetadata.read(at: url, prefixBytes: 64)
    XCTAssertEqual([metadata.width, metadata.height], [300, 200])
  }

  func testAFileWithNoImageIsNotAnImage() throws {
    try library.text("a.jpg")
    XCTAssertThrowsError(try PhotoMetadata.read(at: library.root.appendingPathComponent("a.jpg"))) {
      XCTAssertEqual(($0 as? PhotoMetadataError)?.kind, .notAnImage)
    }
  }

  func testAMissingFileIsUnreadable() {
    XCTAssertThrowsError(try PhotoMetadata.read(at: library.root.appendingPathComponent("no.jpg")))
    {
      XCTAssertEqual(($0 as? PhotoMetadataError)?.kind, .unreadable)
    }
  }
}
