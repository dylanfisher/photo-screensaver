import Darwin
import Foundation
import ImageIO
import Primitives
import UniformTypeIdentifiers

/// What the app keeps from a photo's header: its shown size, and the EXIF fields the info panel
/// and the timeframe filter use. Missing fields are nil.
public struct PhotoMetadata: Equatable, Sendable {
  /// Pixel size as displayed, with EXIF rotation applied.
  public var width: Int
  public var height: Int
  /// EXIF DateTimeOriginal as `YYYY-MM-DD HH:MM:SS`: the camera's clock, in whatever time zone
  /// it was set to. Text in this form sorts by date.
  public var takenAt: String?
  /// EXIF OffsetTimeOriginal, such as `+02:00`, when the camera recorded one.
  public var takenOffset: String?
  public var make: String?
  public var model: String?
  public var lens: String?
  public var fNumber: Double?
  /// In seconds.
  public var exposure: Double?
  public var iso: Int?
  /// In millimeters.
  public var focalLength: Double?
  public var focalLength35mm: Int?
  /// In degrees, negative south and west.
  public var latitude: Double?
  public var longitude: Double?
  /// In meters, negative below sea level.
  public var altitude: Double?
}

public struct PhotoMetadataError: Error, CustomStringConvertible {
  public enum Kind: Sendable {
    /// Opening or reading the file failed, e.g. because the share dropped. Worth trying again.
    case unreadable
    /// The file reads, but ImageIO finds no image in it. Trying again won't help.
    case notAnImage
  }

  public let kind: Kind
  public let description: String
}

extension PhotoMetadata {
  /// Bytes read from the start of a file before parsing. JPEG keeps EXIF in an APP1 segment of
  /// at most 64 KB before the pixels, and HEIC its metadata in the first few KB; this covers
  /// both with room for the ICC and XMP segments that come before a JPEG's size.
  public static let prefixBytes = 128 * 1024
  /// Read size past the prefix, for the files that need the rest.
  static let chunkBytes = 1024 * 1024

  /// Reads the first `prefixBytes` of the file, and the rest only when that isn't enough
  /// (ADR 0005). ImageIO reads a whole file through a data provider, and how much it reads
  /// through a URL is up to the volume, so the file is read here and handed over as data.
  public static func read(at url: URL, prefixBytes: Int = prefixBytes) throws -> PhotoMetadata {
    let file = open(url.path, O_RDONLY)
    guard file >= 0 else { throw unreadable(url, "can't open") }
    defer { close(file) }
    // Hints only: a volume that refuses them reads as usual. Without them the Mac caches each
    // file and reads ahead past the header, which costs memory and NAS time for nothing.
    _ = fcntl(file, F_NOCACHE, 1)
    _ = fcntl(file, F_RDAHEAD, 0)

    var data = try readBytes(file, upTo: prefixBytes, url)
    let wholeFile = data.count < prefixBytes
    if let metadata = parse(data, wholeFile: wholeFile) { return metadata }
    if !wholeFile {
      while true {
        let chunk = try readBytes(file, upTo: chunkBytes, url)
        data.append(chunk)
        if chunk.count < chunkBytes { break }
      }
      if let metadata = parse(data, wholeFile: true) { return metadata }
    }
    throw PhotoMetadataError(kind: .notAnImage, description: "no image in \(url.path)")
  }

  /// Nil when `data` isn't enough: no image size in it, or, for a prefix of a format that can
  /// keep EXIF after the pixels, no EXIF either.
  static func parse(_ data: Data, wholeFile: Bool) -> PhotoMetadata? {
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
      CGImageSourceGetCount(source) > 0,
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      let size = ImageFile.displaySize(properties: props)
    else { return nil }
    let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
    // A JPEG's EXIF comes before its size, so a prefix that holds the size holds any EXIF the
    // file has. HEIF, PNG and TIFF can keep it anywhere.
    if !wholeFile, exif == nil,
      CGImageSourceGetType(source) as String? != UTType.jpeg.identifier
    {
      return nil
    }
    let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
    return PhotoMetadata(
      width: Int(size.width), height: Int(size.height),
      takenAt: (exif?[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(takenAt),
      takenOffset: (exif?[kCGImagePropertyExifOffsetTimeOriginal] as? String).flatMap(offset),
      make: text(tiff[kCGImagePropertyTIFFMake]),
      model: text(tiff[kCGImagePropertyTIFFModel]),
      lens: text(exif?[kCGImagePropertyExifLensModel]),
      fNumber: exif?[kCGImagePropertyExifFNumber] as? Double,
      exposure: exif?[kCGImagePropertyExifExposureTime] as? Double,
      iso: (exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first,
      focalLength: exif?[kCGImagePropertyExifFocalLength] as? Double,
      focalLength35mm: exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int,
      latitude: coordinate(
        gps[kCGImagePropertyGPSLatitude], ref: gps[kCGImagePropertyGPSLatitudeRef], negative: "S",
        limit: 90),
      longitude: coordinate(
        gps[kCGImagePropertyGPSLongitude], ref: gps[kCGImagePropertyGPSLongitudeRef],
        negative: "W", limit: 180),
      altitude: (gps[kCGImagePropertyGPSAltitude] as? Double).map {
        gps[kCGImagePropertyGPSAltitudeRef] as? Int == 1 ? -$0 : $0
      })
  }

  /// `YYYY:MM:DD HH:MM:SS` as `YYYY-MM-DD HH:MM:SS`, or nil for a blank or impossible date,
  /// which cameras without a set clock write as zeros.
  static func takenAt(_ exif: String) -> String? {
    let numbers = exif.split { !("0"..."9").contains($0) }.map(String.init)
    guard numbers.count >= 6, numbers[0].count == 4, numbers[1...5].allSatisfy({ $0.count == 2 }),
      let year = Int(numbers[0]), let month = Int(numbers[1]), let day = Int(numbers[2]),
      let hour = Int(numbers[3]), let minute = Int(numbers[4]), let second = Int(numbers[5]),
      year > 0, (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour),
      (0...59).contains(minute), (0...60).contains(second)
    else { return nil }
    return "\(numbers[0])-\(numbers[1])-\(numbers[2]) \(numbers[3]):\(numbers[4]):\(numbers[5])"
  }

  /// `+HH:MM` or `-HH:MM`, or nil for anything else.
  static func offset(_ exif: String) -> String? {
    let value = Array(exif.trimmingCharacters(in: .whitespaces))
    let digits = [1, 2, 4, 5]
    guard value.count == 6, value[0] == "+" || value[0] == "-", value[3] == ":",
      digits.allSatisfy({ ("0"..."9").contains(value[$0]) })
    else { return nil }
    return String(value)
  }

  /// Trimmed text, or nil when there's none. Cameras pad make and model with spaces and NULs.
  private static func text(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["\0"]))
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func coordinate(_ value: Any?, ref: Any?, negative: String, limit: Double)
    -> Double?
  {
    guard let degrees = value as? Double, abs(degrees) <= limit else { return nil }
    return ref as? String == negative ? -degrees : degrees
  }

  /// Up to `count` bytes, fewer only at the end of the file.
  private static func readBytes(_ file: Int32, upTo count: Int, _ url: URL) throws -> Data {
    var data = Data(count: count)
    var filled = 0
    while filled < count {
      let got: Int = data.withUnsafeMutableBytes { buffer in
        guard let base = buffer.baseAddress else { return 0 }
        return Darwin.read(file, base + filled, count - filled)
      }
      if got < 0 {
        if errno == EINTR { continue }
        throw unreadable(url, "can't read")
      }
      if got == 0 { break }
      filled += got
    }
    data.count = filled
    return data
  }

  private static func unreadable(_ url: URL, _ action: String) -> PhotoMetadataError {
    PhotoMetadataError(
      kind: .unreadable, description: "\(action) \(url.path): \(String(cString: strerror(errno)))")
  }
}
