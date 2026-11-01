import Foundation

/// Looks up what the info panel shows about a photo: its details from the library database,
/// read from the file when the scan hasn't got to it yet, and its place name, cached in the
/// database so each place is looked up once.
public actor PhotoDetails {
  private let library: PhotoLibrary
  private let root: URL
  private let geocoder: any Geocoder
  private let lookupDelay: Double

  /// Seconds a lookup waits before asking the geocoder, so stepping quickly through photos,
  /// which cancels each lookup, doesn't spend Apple's rate limit on photos passed by.
  public static let lookupDelaySeconds = 1.0

  /// Opens its own connection to the database at `databaseURL`, whose photos are in `root`.
  public init(
    databaseURL: URL, root: URL, geocoder: any Geocoder,
    lookupDelay: Double = PhotoDetails.lookupDelaySeconds
  ) throws {
    library = try PhotoLibrary(at: databaseURL)
    self.root = root
    self.geocoder = geocoder
    self.lookupDelay = lookupDelay
  }

  /// Nil when no photo has `id`, e.g. because a scan removed it. Its metadata is nil until the
  /// scan reads it: `readMetadata(of:)` reads it sooner.
  public func photo(_ id: Int64) throws -> PhotoRecord? {
    try library.photo(id)
  }

  /// Reads the details of a photo the scan hasn't got to yet from its file. Doesn't store them:
  /// the scan reads the file again in its turn, and storing results is its job.
  public func readMetadata(of photo: PhotoRecord) async throws -> PhotoMetadata {
    let url = root.appendingPathComponent(photo.path)
    // Detached so a slow NAS read doesn't hold up place lookups on this actor.
    return try await Task.detached { try PhotoMetadata.read(at: url) }.value
  }

  /// The cached name for the place at these coordinates, or nil if none has been looked up.
  public func cachedPlace(latitude: Double, longitude: Double) throws -> CachedPlace? {
    try library.place(at: PlaceKey(latitude: latitude, longitude: longitude))
  }

  /// The place at these coordinates, from the cache at once, or else from the geocoder after
  /// `lookupDelay` seconds; cancelling the task in that time asks nothing. A geocoder error
  /// isn't cached, so the next lookup asks again; finding nothing there is.
  public func lookUpPlace(latitude: Double, longitude: Double) async throws -> CachedPlace {
    let key = PlaceKey(latitude: latitude, longitude: longitude)
    if let cached = try library.place(at: key) { return cached }
    try await Task.sleep(nanoseconds: UInt64(lookupDelay * 1e9))
    // Another photo in the same cell may have been looked up meanwhile.
    if let cached = try library.place(at: key) { return cached }
    // The photo's own coordinates rather than the cell's center, which can be a kilometer
    // away and outside the park or landmark the photo was taken in.
    let place = try await geocoder.place(latitude: latitude, longitude: longitude)
    let result = place?.shortName.map(CachedPlace.named) ?? .unnamed
    try library.store(result, at: key)
    return result
  }
}
