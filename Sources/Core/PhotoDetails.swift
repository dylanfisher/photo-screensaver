import Foundation

/// Looks up what the info panel shows about a photo: its details from the library database,
/// read from the file when the scan hasn't got to it yet, and its place name, cached in the
/// database so each place is looked up once.
public actor PhotoDetails {
  private let library: PhotoLibrary
  private let root: URL
  private let geocoder: any Geocoder

  /// Opens its own connection to the database at `databaseURL`, whose photos are in `root`.
  public init(databaseURL: URL, root: URL, geocoder: any Geocoder) throws {
    library = try PhotoLibrary(at: databaseURL)
    self.root = root
    self.geocoder = geocoder
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

  /// The place at these coordinates, from the cache or else from the geocoder. A geocoder
  /// error isn't cached, so the next lookup asks again; finding nothing there is.
  public func lookUpPlace(latitude: Double, longitude: Double) async throws -> CachedPlace {
    let key = PlaceKey(latitude: latitude, longitude: longitude)
    if let cached = try library.place(at: key) { return cached }
    // The photo's own coordinates rather than the cell's center, which can be a kilometer
    // away and outside the park or landmark the photo was taken in.
    let place = try await geocoder.place(latitude: latitude, longitude: longitude)
    let result = place?.shortName.map(CachedPlace.named) ?? .unnamed
    try library.store(result, at: key)
    return result
  }
}
