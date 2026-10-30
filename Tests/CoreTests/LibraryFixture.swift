import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// A throwaway photo library in a temp folder, so tests never touch the real NAS.
struct LibraryFixture {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  func remove() throws {
    try FileManager.default.removeItem(at: root)
  }

  @discardableResult
  func jpeg(_ path: String, width: Int = 30, height: Int = 20) throws -> URL {
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
      CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }

  func text(_ path: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a photo".utf8).write(to: url)
  }
}
