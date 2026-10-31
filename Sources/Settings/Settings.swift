import Foundation

/// Everything the user can configure. Loaded from a hand-edited JSON file; every key is required,
/// so a typo in a key name fails as a missing key instead of being ignored.
public struct Settings: Codable, Equatable {
  public enum Scaling: String, Codable {
    /// Full bleed: cover the screen, cropping the edges that don't fit.
    case fill
    /// Show the whole photo, with black bars where the aspect ratios differ.
    case fit
  }

  public enum Orientation: String, Codable {
    case any, landscape, portrait
  }

  public struct Motion: Codable, Equatable {
    public var enabled: Bool
    /// Longest time between camera checks.
    public var checkEveryMinutes: Double
    /// Time before the check that confirms an empty room, and the first gap between checks
    /// while the display is off.
    public var quickCheckEverySeconds: Double
    public var sampleSeconds: Double
    /// Fraction of any one cell of the camera image's grid (0–1) that must change to count as
    /// motion.
    public var threshold: Double
  }

  /// Times of day when the slideshow doesn't start on its own and motion checks don't run. A
  /// running slideshow stops and the display sleeps as they begin.
  public struct OffHours: Codable, Equatable {
    public var enabled: Bool
    /// "HH:mm", 24-hour, local time. A `start` later than `end` spans midnight.
    public var start: String
    public var end: String

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
      guard enabled else { return false }
      guard let start = Self.minuteOfDay(start), let end = Self.minuteOfDay(end) else {
        preconditionFailure("validate() rejects off-hours times that aren't HH:mm")
      }
      let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
      return start < end ? (start..<end).contains(now) : now >= start || now < end
    }

    /// Minutes after midnight for an "HH:mm" time, or nil if it isn't one.
    static func minuteOfDay(_ time: String) -> Int? {
      let parts = time.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2,
        parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { ("0"..."9").contains($0) } }),
        let hour = Int(parts[0]), let minute = Int(parts[1]), hour < 24, minute < 60
      else { return nil }
      return hour * 60 + minute
    }
  }

  /// Folder the photos are read from, searched recursively. Never written to.
  public var libraryPath: String
  /// Minutes without keyboard or mouse input before the slideshow starts.
  public var idleMinutes: Double
  public var slideSeconds: Double
  public var transitionSeconds: Double
  public var scaling: Scaling
  public var orientation: Orientation
  public var kenBurns: Bool
  /// Photos decoded ahead of the one on screen.
  public var preloadCount: Int
  public var motion: Motion
  public var offHours: OffHours

  public var libraryURL: URL {
    URL(fileURLWithPath: (libraryPath as NSString).expandingTildeInPath, isDirectory: true)
  }
}

public struct SettingsError: Error, CustomStringConvertible {
  public let description: String
}

extension Settings {
  /// `~/Library/Application Support/photo-screensaver/config.json`
  public static var fileURL: URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    return support[0].appendingPathComponent("photo-screensaver/config.json")
  }

  /// Written when no config file exists, so there is always a complete file to edit.
  public static let starter = Settings(
    libraryPath: "/Volumes/main/photos/public",
    idleMinutes: 5,
    slideSeconds: 15,
    transitionSeconds: 1.5,
    scaling: .fill,
    orientation: .any,
    kenBurns: true,
    preloadCount: 3,
    motion: Motion(
      enabled: false, checkEveryMinutes: 5, quickCheckEverySeconds: 15, sampleSeconds: 4,
      threshold: 0.2),
    offHours: OffHours(enabled: false, start: "00:00", end: "09:00")
  )

  public static func decode(_ data: Data) throws -> Settings {
    let settings: Settings
    do {
      settings = try JSONDecoder().decode(Settings.self, from: data)
    } catch let error as DecodingError {
      throw SettingsError(description: describe(error))
    }
    try settings.validate()
    return settings
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(self)
  }

  /// Writes `starter` to the config file if there is none, so there is always one to edit.
  /// Only at launch: during a reload a missing file is usually an editor mid-save.
  public static func createIfMissing(at url: URL = fileURL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try starter.encoded().write(to: url, options: .atomic)
  }

  public static func load(at url: URL = fileURL) throws -> Settings {
    try decode(Data(contentsOf: url))
  }

  func validate() throws {
    // Upper bounds keep durations sane, well inside what timers can represent.
    let ranges: [(String, Double, Double)] = [
      ("idleMinutes", idleMinutes, 24 * 60),
      ("slideSeconds", slideSeconds, 60 * 60),
      ("motion.checkEveryMinutes", motion.checkEveryMinutes, 24 * 60),
      (
        "motion.quickCheckEverySeconds", motion.quickCheckEverySeconds,
        motion.checkEveryMinutes * 60
      ),
      ("motion.sampleSeconds", motion.sampleSeconds, 60),
    ]
    for (key, value, max) in ranges where !(value > 0 && value <= max) {
      throw SettingsError(
        description: "\(key) must be greater than 0 and at most \(max), got \(value)")
    }
    if transitionSeconds < 0 || transitionSeconds >= slideSeconds {
      throw SettingsError(
        description:
          "transitionSeconds must be between 0 and slideSeconds, got \(transitionSeconds)"
      )
    }
    if preloadCount < 1 {
      throw SettingsError(description: "preloadCount must be at least 1, got \(preloadCount)")
    }
    if !(0...1).contains(motion.threshold) {
      throw SettingsError(
        description: "motion.threshold must be between 0 and 1, got \(motion.threshold)")
    }
    for (key, time) in [("offHours.start", offHours.start), ("offHours.end", offHours.end)]
    where OffHours.minuteOfDay(time) == nil {
      throw SettingsError(
        description: "\(key) must be a 24-hour time like \"09:00\", got \"\(time)\"")
    }
    if offHours.start == offHours.end {
      throw SettingsError(description: "offHours.start and offHours.end must differ")
    }
    if libraryPath.isEmpty {
      throw SettingsError(description: "libraryPath is empty")
    }
  }

  private static func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context, _ last: CodingKey? = nil) -> String {
      (context.codingPath + (last.map { [$0] } ?? [])).map(\.stringValue).joined(separator: ".")
    }
    switch error {
    case .keyNotFound(let key, let context):
      return "missing key \"\(path(context, key))\""
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      return "wrong type for \"\(path(context))\": \(context.debugDescription)"
    case .dataCorrupted(let context):
      if context.codingPath.isEmpty {
        return "not valid JSON: \(context.underlyingError?.localizedDescription ?? "")"
      }
      return "bad value for \"\(path(context))\": \(context.debugDescription)"
    @unknown default:
      return error.localizedDescription
    }
  }
}
