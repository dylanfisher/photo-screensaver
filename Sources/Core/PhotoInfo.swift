import Foundation

/// The text of the photo info panel. Fields the photo doesn't have are left out.
public struct PhotoInfo: Equatable {
  /// Where and when, shown larger: the place name, or the coordinates until it's known, and
  /// the capture date and time.
  public var headlines: [String]
  /// Shown smaller: camera, lens, exposure, size, and the folder and file name.
  public var details: [String]

  /// `path` is relative to the library folder. `place` is the name looked up for the photo's
  /// location, if any yet.
  public init(path: String, metadata: PhotoMetadata?, place: String?, locale: Locale = .current) {
    headlines = []
    details = []
    if let metadata {
      if let latitude = metadata.latitude, let longitude = metadata.longitude {
        headlines.append(place ?? Self.coordinates(latitude: latitude, longitude: longitude))
      }
      if let date = metadata.takenAt.flatMap({
        Self.date($0, offset: metadata.takenOffset, locale: locale)
      }) {
        headlines.append(date)
      }
      let camera = Self.camera(make: metadata.make, model: metadata.model)
      let lines = [
        camera,
        metadata.lens.flatMap { $0 == camera ? nil : $0 },
        Self.exposure(metadata),
        Self.dimensions(width: metadata.width, height: metadata.height),
      ]
      details.append(contentsOf: lines.compactMap { $0 })
    }
    details.append(Self.file(path))
  }

  /// Like "35.6595° N, 139.7005° E".
  static func coordinates(latitude: Double, longitude: Double) -> String {
    String(
      format: "%.4f° %@, %.4f° %@", abs(latitude), latitude < 0 ? "S" : "N", abs(longitude),
      longitude < 0 ? "W" : "E")
  }

  /// The capture date and time in `locale`'s words, like "Saturday, 14 June 2014 at 18:32",
  /// on the camera's clock. With an offset the time zone follows it, like "GMT+2"; the time
  /// shown is the same either way, never moved into the Mac's time zone. Nil if `takenAt`
  /// isn't `YYYY-MM-DD HH:MM:SS`.
  static func date(_ takenAt: String, offset: String?, locale: Locale) -> String? {
    let numbers = takenAt.split { !("0"..."9").contains($0) }.compactMap { Int($0) }
    let zone = offset.flatMap(timeZone)
    // Without an offset the time is read and shown in GMT, which leaves it as the camera had
    // it.
    guard numbers.count == 6, let shownIn = zone ?? TimeZone(secondsFromGMT: 0) else {
      return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = shownIn
    let components = DateComponents(
      year: numbers[0], month: numbers[1], day: numbers[2], hour: numbers[3],
      minute: numbers[4], second: numbers[5])
    guard let date = calendar.date(from: components) else { return nil }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = shownIn
    formatter.setLocalizedDateFormatFromTemplate(zone == nil ? "EEEEdMMMMyjmm" : "EEEEdMMMMyjmmz")
    return formatter.string(from: date)
  }

  /// `+HH:MM` or `-HH:MM` as a time zone.
  private static func timeZone(_ offset: String) -> TimeZone? {
    let sign: Int
    switch offset.first {
    case "+": sign = 1
    case "-": sign = -1
    default: return nil
    }
    let parts = offset.dropFirst().split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    return TimeZone(secondsFromGMT: sign * (parts[0] * 3600 + parts[1] * 60))
  }

  /// Make and model, without the make twice when the model starts with it, as in "Canon EOS 5D
  /// Mark III" or "NIKON D750" from "NIKON CORPORATION", and without words like "Corporation".
  static func camera(make: String?, model: String?) -> String? {
    let brand = make.map(brandName)
    guard let model else { return brand }
    guard let brand else { return model }
    let brandWords = Set(brand.lowercased().split(separator: " "))
    if let first = model.lowercased().split(separator: " ").first, brandWords.contains(first) {
      return model
    }
    return "\(brand) \(model)"
  }

  /// Words that follow a brand in a camera's make, compared lowercased without dots and commas.
  private static let companyWords: Set<String> = [
    "corporation", "corp", "co", "ltd", "coltd", "inc", "company", "imaging", "optical",
  ]

  /// The make without trailing company words, such as "OLYMPUS" from "OLYMPUS IMAGING CORP.".
  private static func brandName(_ make: String) -> String {
    var words = make.split(separator: " ")
    while words.count > 1,
      let last = words.last,
      companyWords.contains(last.lowercased().filter { $0 != "." && $0 != "," })
    {
      words.removeLast()
    }
    return words.joined(separator: " ")
  }

  /// Like "ƒ/2.8 · 1/250 s · ISO 400 · 35 mm", with whichever of those the photo has.
  static func exposure(_ metadata: PhotoMetadata) -> String? {
    var parts: [String] = []
    if let fNumber = metadata.fNumber, fNumber > 0 { parts.append("ƒ/\(decimal(fNumber))") }
    if let seconds = metadata.exposure, seconds > 0 { parts.append(shutter(seconds)) }
    if let iso = metadata.iso, iso > 0 { parts.append("ISO \(iso)") }
    if let focal = focalLength(metadata.focalLength, equivalent: metadata.focalLength35mm) {
      parts.append(focal)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// "1/250 s" below 0.4 s, as cameras show it, and "0.5 s" or "2 s" from there.
  private static func shutter(_ seconds: Double) -> String {
    seconds < 0.4 ? "1/\(Int((1 / seconds).rounded())) s" : "\(decimal(seconds)) s"
  }

  /// "50 mm", or with a 35mm equivalent that differs, "4.2 mm (26 mm equiv.)".
  private static func focalLength(_ actual: Double?, equivalent: Int?) -> String? {
    let actual = actual.flatMap { $0 > 0 ? $0 : nil }
    let equivalent = equivalent.flatMap { $0 > 0 ? $0 : nil }
    switch (actual, equivalent) {
    case (let actual?, let equivalent?) where Int(actual.rounded()) != equivalent:
      return "\(decimal(actual)) mm (\(equivalent) mm equiv.)"
    case (let actual?, _):
      return "\(decimal(actual)) mm"
    case (nil, let equivalent?):
      return "\(equivalent) mm equiv."
    case (nil, nil):
      return nil
    }
  }

  /// Like "24.2 MP · 6000 × 4000", leaving out megapixels for an image under 0.1 MP.
  static func dimensions(width: Int, height: Int) -> String {
    let pixels = "\(width) × \(height)"
    let megapixels = Double(width * height) / 1_000_000
    return megapixels < 0.1 ? pixels : "\(decimal(megapixels)) MP · \(pixels)"
  }

  /// The folder the photo is in and its file name, like "Japan 2014 / IMG_1234.JPG", since
  /// folders are often named for the trip or event. Only the file name for a photo at the top
  /// of the library.
  static func file(_ path: String) -> String {
    let parts = path.split(separator: "/")
    return parts.suffix(2).joined(separator: " / ")
  }

  /// One decimal place at most, and none when it's zero: "2.8", "8".
  private static func decimal(_ value: Double) -> String {
    let text = String(format: "%.1f", value)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
  }
}
