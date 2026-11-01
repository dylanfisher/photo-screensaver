import Accelerate
import CoreGraphics
import Foundation
import ImageIO

public struct ImageFileError: Error, CustomStringConvertible {
  public let description: String
}

/// An image file opened with ImageIO. Opening reads only the header, so checking size and
/// orientation is cheap even over a network share.
public struct ImageFile {
  public let url: URL
  private let source: CGImageSource

  public init(url: URL) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetCount(source) > 0
    else { throw ImageFileError(description: "can't open \(url.path)") }
    self.url = url
    self.source = source
  }

  /// Pixel size as displayed, with EXIF rotation applied (a rotated portrait reports as portrait).
  public func displaySize() throws -> CGSize {
    guard let size = Self.displaySize(properties: try properties()) else {
      throw ImageFileError(description: "no pixel size in \(url.path)")
    }
    return size
  }

  /// `displaySize()` from properties ImageIO already read, or nil when they have no pixel size.
  public static func displaySize(properties props: [CFString: Any]) -> CGSize? {
    guard
      let width = props[kCGImagePropertyPixelWidth] as? Int,
      let height = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return Orientation(exif: props).swapsAxes
      ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  /// Decodes with EXIF rotation applied, scaled so the longer edge is at most `maxPixelSize`.
  /// Never scales up. The pixels are decoded before returning, so drawing doesn't stall.
  ///
  /// Avoids ImageIO's thumbnail API and CoreGraphics drawing on purpose: both leave the decoded
  /// pixels in a process-wide CoreGraphics cache that grows to gigabytes over a slideshow.
  public func decode(maxPixelSize: Int) throws -> CGImage {
    let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
      throw ImageFileError(description: "can't decode \(url.path)")
    }
    let orientation = Orientation(exif: try properties())
    let longEdge = max(image.width, image.height)
    if orientation == .up, longEdge <= maxPixelSize { return image }
    let scale = min(1, Double(maxPixelSize) / Double(longEdge))
    return try Self.transform(image, scale: scale, orientation: orientation)
  }

  private func properties() throws -> [CFString: Any] {
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
      throw ImageFileError(description: "no image properties in \(url.path)")
    }
    return props
  }

  /// Scales, then rotates and mirrors upright, with vImage rather than CoreGraphics drawing.
  private static func transform(
    _ image: CGImage, scale: Double, orientation: Orientation
  ) throws -> CGImage {
    // Keep the photo's own color space (often Display P3); convert other models to sRGB.
    guard
      let space = image.colorSpace.flatMap({ $0.model == .rgb ? $0 : nil })
        ?? CGColorSpace(name: CGColorSpace.sRGB),
      let format = vImage_CGImageFormat(
        bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue))
    else { throw ImageFileError(description: "unsupported color space") }

    var buffer = try vImage_Buffer(cgImage: image, format: format)
    defer { buffer.free() }

    if scale < 1 {
      var scaled = try vImage_Buffer(
        width: Int((Double(buffer.width) * scale).rounded()),
        height: Int((Double(buffer.height) * scale).rounded()),
        bitsPerPixel: format.bitsPerPixel)
      let error = vImageScale_ARGB8888(
        &buffer, &scaled, nil, vImage_Flags(kvImageHighQualityResampling))
      buffer.free()
      buffer = scaled
      try check(error, "scale")
    }

    if orientation.rotation != UInt8(kRotate0DegreesClockwise) {
      let swaps = orientation.swapsAxes
      var rotated = try vImage_Buffer(
        width: Int(swaps ? buffer.height : buffer.width),
        height: Int(swaps ? buffer.width : buffer.height),
        bitsPerPixel: format.bitsPerPixel)
      var black: [UInt8] = [0, 0, 0, 0]
      let error = vImageRotate90_ARGB8888(
        &buffer, &rotated, orientation.rotation, &black, vImage_Flags(kvImageNoFlags))
      buffer.free()
      buffer = rotated
      try check(error, "rotate")
    }

    if orientation.mirrored {
      try check(
        vImageHorizontalReflect_ARGB8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags)),
        "mirror")
    }

    return try buffer.createCGImage(format: format)
  }

  private static func check(_ error: vImage_Error, _ step: String) throws {
    guard error == kvImageNoError else {
      throw ImageFileError(description: "vImage \(step) failed with error \(error)")
    }
  }
}

/// EXIF orientation as the steps that turn the stored pixels upright: rotate, then mirror.
private struct Orientation: Equatable {
  let rotation: UInt8
  let mirrored: Bool

  static let up = Orientation(rotation: UInt8(kRotate0DegreesClockwise), mirrored: false)

  init(rotation: UInt8, mirrored: Bool) {
    self.rotation = rotation
    self.mirrored = mirrored
  }

  init(exif props: [CFString: Any]) {
    // Values 1–8 from the EXIF spec; missing or unknown means upright.
    switch props[kCGImagePropertyOrientation] as? Int ?? 1 {
    case 2: self.init(rotation: UInt8(kRotate0DegreesClockwise), mirrored: true)
    case 3: self.init(rotation: UInt8(kRotate180DegreesClockwise), mirrored: false)
    case 4: self.init(rotation: UInt8(kRotate180DegreesClockwise), mirrored: true)
    case 5: self.init(rotation: UInt8(kRotate90DegreesClockwise), mirrored: true)
    case 6: self.init(rotation: UInt8(kRotate90DegreesClockwise), mirrored: false)
    case 7: self.init(rotation: UInt8(kRotate270DegreesClockwise), mirrored: true)
    case 8: self.init(rotation: UInt8(kRotate270DegreesClockwise), mirrored: false)
    default: self = .up
    }
  }

  var swapsAxes: Bool {
    rotation == UInt8(kRotate90DegreesClockwise) || rotation == UInt8(kRotate270DegreesClockwise)
  }
}
