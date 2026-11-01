/// Which photos the slideshow shows, by when they were taken. Every kind but `all` leaves out
/// photos without a capture date. The relative kinds are worked out again from the date each
/// time the slideshow has shown every photo, so they follow the calendar.
///
/// In the config file it's an object with a `kind` and that kind's fields only:
/// `{"kind": "all"}`, `{"kind": "onThisDay"}`, `{"kind": "lastMonths", "months": 12}`, or
/// `{"kind": "range", "from": "2014-01", "to": "2014-12"}`.
public enum Timeframe: Codable, Equatable, Sendable {
  case all
  /// Taken within `onThisDayDays` days either side of today's month and day, in any year.
  case onThisDay
  /// Taken since today's date `months` months ago.
  case lastMonths(Int)
  /// Taken from the start of `from` to the end of `to`. A single year is January to December.
  case range(from: CaptureMonth, to: CaptureMonth)

  /// Days either side of today that "on this day" takes in, so a day with no photos in some
  /// years still shows the ones from that week.
  public static let onThisDayDays = 3
  /// A hundred years, well past any photo library.
  static let maxMonths = 1200

  /// The whole of `year`.
  public static func year(_ year: Int) -> Timeframe {
    .range(from: CaptureMonth(year: year, month: 1), to: CaptureMonth(year: year, month: 12))
  }

  /// Shown in the timeframe picker, the menu and the message when one is chosen, like "2014"
  /// or "Mar 2014 – Jun 2015".
  public var title: String {
    switch self {
    case .all: return "All time"
    case .onThisDay: return "On this day"
    case .lastMonths(let months): return months == 1 ? "Last month" : "Last \(months) months"
    case .range(let from, let to):
      if from.month == 1, to.month == 12 {
        return from.year == to.year ? "\(from.year)" : "\(from.year) – \(to.year)"
      }
      if from == to { return "\(from.monthName) \(from.year)" }
      if from.year == to.year { return "\(from.monthName) – \(to.monthName) \(to.year)" }
      return "\(from.monthName) \(from.year) – \(to.monthName) \(to.year)"
    }
  }

  func validate() throws {
    switch self {
    case .all, .onThisDay:
      break
    case .lastMonths(let months):
      if !(1...Self.maxMonths).contains(months) {
        throw SettingsError(
          description: "timeframe.months must be from 1 to \(Self.maxMonths), got \(months)")
      }
    case .range(let from, let to):
      if to < from {
        throw SettingsError(
          description: "timeframe.from must not be after timeframe.to, got \(from) and \(to)")
      }
    }
  }

  private enum Kind: String, Codable {
    case all, onThisDay, lastMonths, range
  }

  /// Any key, so one that doesn't belong to the kind can be named in the error.
  private struct Key: CodingKey, Hashable {
    let stringValue: String
    init(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }

    static let kind = Key(stringValue: "kind")
    static let months = Key(stringValue: "months")
    static let from = Key(stringValue: "from")
    static let to = Key(stringValue: "to")
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: Key.self)
    let kind = try container.decode(Kind.self, forKey: .kind)
    let fields: [Key]
    switch kind {
    case .all:
      self = .all
      fields = []
    case .onThisDay:
      self = .onThisDay
      fields = []
    case .lastMonths:
      self = .lastMonths(try container.decode(Int.self, forKey: .months))
      fields = [.months]
    case .range:
      self = .range(
        from: try container.decode(CaptureMonth.self, forKey: .from),
        to: try container.decode(CaptureMonth.self, forKey: .to))
      fields = [.from, .to]
    }
    // A field of another kind, or a misspelled one, would otherwise be ignored.
    if let extra = container.allKeys.first(where: { $0 != .kind && !fields.contains($0) }) {
      throw DecodingError.dataCorruptedError(
        forKey: extra, in: container,
        debugDescription: "\"\(kind.rawValue)\" timeframes have no \"\(extra.stringValue)\"")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: Key.self)
    switch self {
    case .all:
      try container.encode(Kind.all, forKey: .kind)
    case .onThisDay:
      try container.encode(Kind.onThisDay, forKey: .kind)
    case .lastMonths(let months):
      try container.encode(Kind.lastMonths, forKey: .kind)
      try container.encode(months, forKey: .months)
    case .range(let from, let to):
      try container.encode(Kind.range, forKey: .kind)
      try container.encode(from, forKey: .from)
      try container.encode(to, forKey: .to)
    }
  }
}
