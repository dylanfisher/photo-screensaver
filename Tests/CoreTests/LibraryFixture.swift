import Core
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// A throwaway photo library in a temp folder, so tests never touch the real NAS. Its database
/// sits beside the library folder, never inside it.
struct LibraryFixture {
  /// Holds the library folder and the database.
  let base: URL
  let root: URL
  let database: URL

  init() throws {
    base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    root = base.appendingPathComponent("library")
    database = base.appendingPathComponent("library.sqlite")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() throws {
    try FileManager.default.removeItem(at: base)
  }

  /// Camera details as `CGImageDestination` writes them, taken 2021-07-04 18:30 in New York.
  static let cameraProperties: [CFString: Any] = [
    kCGImagePropertyExifDictionary: [
      kCGImagePropertyExifDateTimeOriginal: "2021:07:04 18:30:00",
      kCGImagePropertyExifOffsetTimeOriginal: "-04:00",
      kCGImagePropertyExifLensModel: "iPhone 12 back camera 4.2mm f/1.6",
      kCGImagePropertyExifFNumber: 1.6,
      kCGImagePropertyExifExposureTime: 0.004,
      kCGImagePropertyExifISOSpeedRatings: [32],
      kCGImagePropertyExifFocalLength: 4.2,
      kCGImagePropertyExifFocalLenIn35mmFilm: 26,
    ],
    kCGImagePropertyTIFFDictionary: [
      kCGImagePropertyTIFFMake: "Apple",
      kCGImagePropertyTIFFModel: "iPhone 12",
    ],
    kCGImagePropertyGPSDictionary: [
      kCGImagePropertyGPSLatitude: 40.7484,
      kCGImagePropertyGPSLatitudeRef: "N",
      kCGImagePropertyGPSLongitude: 73.9857,
      kCGImagePropertyGPSLongitudeRef: "W",
      kCGImagePropertyGPSAltitude: 12.5,
      kCGImagePropertyGPSAltitudeRef: 0,
    ],
  ]

  /// EXIF with only a capture date, as `YYYY:MM:DD HH:MM:SS`.
  static func taken(_ date: String) -> [CFString: Any] {
    [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: date]]
  }

  @discardableResult
  func jpeg(
    _ path: String, width: Int = 30, height: Int = 20, properties: [CFString: Any] = [:]
  ) throws -> URL {
    try image(path, type: .jpeg, width: width, height: height, properties: properties)
  }

  @discardableResult
  func image(
    _ path: String, type: UTType, width: Int = 30, height: Int = 20,
    properties: [CFString: Any] = [:]
  ) throws -> URL {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }

  func text(_ path: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a photo".utf8).write(to: url)
  }

  /// Sets the database up for this library, as the app does at launch.
  func open() throws -> PhotoLibrary {
    let library = try PhotoLibrary(at: database)
    try library.use(root: root)
    return library
  }

  @discardableResult
  func scan() throws -> LibraryScan.Summary {
    _ = try open()
    return try LibraryScan(databaseURL: database, root: root).run()
  }

  /// Every photo's path, sorted.
  func paths() throws -> [String] {
    let library = try PhotoLibrary(at: database)
    return try library.photoIDs().compactMap { try library.photo($0)?.path }.sorted()
  }
}
