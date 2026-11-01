/// What a reverse geocoder found at a location, reduced to the fields a short place name uses.
public struct Place: Equatable, Sendable {
  /// The geocoder's name for the spot: a landmark's name, or a street address.
  public var name: String?
  /// The street, to tell an address in `name` from a landmark.
  public var thoroughfare: String?
  /// A neighborhood, such as Shibuya.
  public var subLocality: String?
  /// A city.
  public var locality: String?
  /// A state or prefecture.
  public var administrativeArea: String?
  public var country: String?
  public var inlandWater: String?
  public var ocean: String?
  /// Parks, landmarks and the like the location is in, such as Yosemite National Park.
  public var areasOfInterest: [String]

  public init(
    name: String? = nil, thoroughfare: String? = nil, subLocality: String? = nil,
    locality: String? = nil, administrativeArea: String? = nil, country: String? = nil,
    inlandWater: String? = nil, ocean: String? = nil, areasOfInterest: [String] = []
  ) {
    self.name = name
    self.thoroughfare = thoroughfare
    self.subLocality = subLocality
    self.locality = locality
    self.administrativeArea = administrativeArea
    self.country = country
    self.inlandWater = inlandWater
    self.ocean = ocean
    self.areasOfInterest = areasOfInterest
  }

  /// A name a viewer recognizes, like "Shibuya, Tokyo, Japan" or "Yosemite National Park,
  /// California, United States": the most specific named area, the city, or the state when
  /// there's no city, and the country. Never a street address. A lake or sea when the location
  /// has nothing else. Nil when the geocoder gave nothing usable.
  public var shortName: String? {
    let specific = areasOfInterest.first ?? landmark ?? subLocality
    var parts: [String] = []
    for part in [specific, locality ?? administrativeArea, country] {
      guard let part = part.flatMap(Self.text),
        !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame })
      else { continue }
      parts.append(part)
    }
    if parts.isEmpty, let water = (inlandWater ?? ocean).flatMap(Self.text) {
      parts.append(water)
    }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }

  /// `name` when it names a place rather than an address: geocoders put the street number and
  /// street there for a location on a street.
  private var landmark: String? {
    guard let name = name.flatMap(Self.text), name.first?.isNumber != true else { return nil }
    if let street = thoroughfare.flatMap(Self.text), name.localizedCaseInsensitiveContains(street) {
      return nil
    }
    return name
  }

  private static func text(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
