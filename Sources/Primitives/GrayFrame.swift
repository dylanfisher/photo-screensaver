/// A small grayscale image, used to compare camera frames.
public struct GrayFrame: Equatable {
  public let width: Int
  public let height: Int
  public let pixels: [UInt8]

  public init(width: Int, height: Int, pixels: [UInt8]) {
    precondition(pixels.count == width * height, "pixel count must be width × height")
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// Samples an 8-bit single-channel buffer (such as a camera's luma plane) down to
  /// `width` × `height` by nearest neighbor.
  public init(
    sampling base: UnsafePointer<UInt8>, width srcWidth: Int, height srcHeight: Int,
    bytesPerRow: Int, toWidth width: Int, height: Int
  ) {
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      let row = base + (y * srcHeight / height) * bytesPerRow
      for x in 0..<width {
        pixels[y * width + x] = row[x * srcWidth / width]
      }
    }
    self.init(width: width, height: height, pixels: pixels)
  }

  /// Fraction of pixels (0–1) whose brightness differs from `other` by more than
  /// `pixelThreshold`. The threshold keeps sensor noise from counting as change.
  public func changedFraction(from other: GrayFrame, pixelThreshold: UInt8 = 25) -> Double {
    precondition(width == other.width && height == other.height, "frames must match in size")
    var changed = 0
    for i in pixels.indices
    where abs(Int(pixels[i]) - Int(other.pixels[i])) > Int(pixelThreshold) {
      changed += 1
    }
    return Double(changed) / Double(pixels.count)
  }
}
