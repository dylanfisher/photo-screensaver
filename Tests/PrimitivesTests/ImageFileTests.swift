import CoreGraphics
import ImageIO
import Primitives
import UniformTypeIdentifiers
import XCTest

final class ImageFileTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: dir)
  }

  func testDisplaySizeAppliesExifRotation() throws {
    let upright = try writeJPEG(width: 60, height: 40, orientation: 1)
    let rotated = try writeJPEG(width: 60, height: 40, orientation: 6)
    XCTAssertEqual(try ImageFile(url: upright).displaySize(), CGSize(width: 60, height: 40))
    XCTAssertEqual(try ImageFile(url: rotated).displaySize(), CGSize(width: 40, height: 60))
  }

  func testDecodeScalesDownToMaxPixelSize() throws {
    let image = try ImageFile(url: writeJPEG(width: 400, height: 200)).decode(maxPixelSize: 100)
    XCTAssertEqual(image.width, 100)
    XCTAssertEqual(image.height, 50)
  }

  func testDecodeNeverScalesUp() throws {
    let image = try ImageFile(url: writeJPEG(width: 40, height: 30)).decode(maxPixelSize: 1000)
    XCTAssertEqual(image.width, 40)
    XCTAssertEqual(image.height, 30)
  }

  func testDecodeAppliesExifRotation() throws {
    let url = try writeJPEG(width: 60, height: 40, orientation: 6)
    let image = try ImageFile(url: url).decode(maxPixelSize: 1000)
    XCTAssertEqual(image.width, 40)
    XCTAssertEqual(image.height, 60)
  }

  func testAllExifOrientationsMatchImageIO() throws {
    for orientation in 1...8 {
      let url = try writeQuadrants(orientation: orientation)
      let expected = try XCTUnwrap(imageIOUpright(url))
      for maxPixelSize in [1000, 30] {
        let actual = try ImageFile(url: url).decode(maxPixelSize: maxPixelSize)
        XCTAssertEqual(
          quadrantColors(actual), quadrantColors(expected),
          "orientation \(orientation), max \(maxPixelSize)")
      }
    }
  }

  func testNonImageFileThrows() throws {
    let url = dir.appendingPathComponent("notes.jpg")
    try Data("not an image".utf8).write(to: url)
    XCTAssertThrowsError(try ImageFile(url: url).decode(maxPixelSize: 100))
  }

  /// 60×40, with a distinct color in each quadrant, stored losslessly as TIFF.
  private func writeQuadrants(orientation: Int) throws -> URL {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: 60, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    // CoreGraphics' origin is bottom-left.
    let quadrants: [(CGRect, (CGFloat, CGFloat, CGFloat))] = [
      (CGRect(x: 0, y: 20, width: 30, height: 20), (1, 0, 0)),
      (CGRect(x: 30, y: 20, width: 30, height: 20), (0, 1, 0)),
      (CGRect(x: 0, y: 0, width: 30, height: 20), (0, 0, 1)),
      (CGRect(x: 30, y: 0, width: 30, height: 20), (1, 1, 1)),
    ]
    for (rect, (r, g, b)) in quadrants {
      context.setFillColor(red: r, green: g, blue: b, alpha: 1)
      context.fill(rect)
    }
    let image = try XCTUnwrap(context.makeImage())
    let url = dir.appendingPathComponent("\(UUID().uuidString).tiff")
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }

  private func imageIOUpright(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1000,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// Rounded RGB at the center of each quadrant, top-left first.
  private func quadrantColors(_ image: CGImage) -> [[Int]] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    // Bitmap memory starts at the top row.
    let points = [(1, 1), (3, 1), (1, 3), (3, 3)].map { (width * $0 / 4, height * $1 / 4) }
    return points.map { x, y in
      let i = (y * width + x) * 4
      return (0..<3).map { (Int(pixels[i + $0]) + 64) / 128 }
    }
  }

  private func writeJPEG(width: Int, height: Int, orientation: Int = 1) throws -> URL {
    let context = try XCTUnwrap(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())

    let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    let props = [kCGImagePropertyOrientation: orientation] as CFDictionary
    CGImageDestinationAddImage(destination, image, props)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return url
  }
}
