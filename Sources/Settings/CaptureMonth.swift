import Foundation

/// A calendar month, for choosing photos by when they were taken. Written `YYYY-MM` in the
/// config file, the same text every capture date in the month starts with.
public struct CaptureMonth: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
  public let year: Int
  /// 1 to 12.
  public let month: Int

  public init(year: Int, month: Int) {
    precondition((1...12).contains(month), "month \(month) is not 1 to 12")
    self.year = year
    self.month = month
  }

  /// Reads `YYYY-MM`, such as `"2014-01"`.
  public init(parsing text: String) throws {
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
      parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
      let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
    else {
      throw SettingsError(description: "\"\(text)\" isn't a month like \"2014-01\"")
    }
    self.init(year: year, month: month)
  }

  public static func < (a: CaptureMonth, b: CaptureMonth) -> Bool {
    (a.year, a.month) < (b.year, b.month)
  }

  /// `YYYY-MM`, which every `PhotoMetadata.takenAt` in this month starts with and sorts after.
  public var prefix: String { String(format: "%04d-%02d", year, month) }

  public var description: String { prefix }

  public var next: CaptureMonth {
    month == 12
      ? CaptureMonth(year: year + 1, month: 1) : CaptureMonth(year: year, month: month + 1)
  }

  /// The month `months` later, or earlier for a negative count.
  public func adding(months: Int) -> CaptureMonth {
    let index = year * 12 + (month - 1) + months
    // Division rounds toward zero, so below year 0 the year needs rounding down.
    let year = index / 12 - (index % 12 < 0 ? 1 : 0)
    return CaptureMonth(year: year, month: index - year * 12 + 1)
  }

  /// Short English month names, as the rest of the app's text is English.
  static let monthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  /// Like "Mar".
  public var monthName: String { Self.monthNames[month - 1] }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    do {
      try self.init(parsing: container.decode(String.self))
    } catch let error as SettingsError {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: error.description)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(prefix)
  }
}
