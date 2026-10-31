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

  /// The largest fraction (0–1) of pixels, within any one cell of a `columns` × `rows` grid, whose
  /// brightness differs from `other` by more than `pixelThreshold`. Measured per cell so a small or
  /// distant change isn't diluted by the still rest of the image. The difference in average
  /// brightness is taken out first, so an exposure shift or a lamp switching on doesn't count as
  /// change everywhere. The threshold keeps sensor noise from counting as change.
  public func largestCellChange(
    from other: GrayFrame, columns: Int, rows: Int, pixelThreshold: UInt8 = 25
  ) -> Double {
    precondition(width == other.width && height == other.height, "frames must match in size")
    precondition(
      (1...width).contains(columns) && (1...height).contains(rows),
      "grid must fit within the frame")
    let offset = Int((other.mean - mean).rounded())
    var changed = [Int](repeating: 0, count: columns * rows)
    var total = changed
    for y in 0..<height {
      let rowStart = (y * rows / height) * columns
      for x in 0..<width {
        let cell = rowStart + x * columns / width
        let i = y * width + x
        total[cell] += 1
        if abs(Int(pixels[i]) - Int(other.pixels[i]) + offset) > Int(pixelThreshold) {
          changed[cell] += 1
        }
      }
    }
    return zip(changed, total).map { Double($0) / Double($1) }.max() ?? 0
  }

  private var mean: Double {
    Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
  }
}
