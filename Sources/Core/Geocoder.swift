/// Finds what is at a location, over the network. A protocol so the place-name cache can be
/// tested without it.
public protocol Geocoder: Sendable {
  /// The place at these coordinates, or nil when the service knows of nothing there. Throws
  /// when it can't answer now, such as offline, rate-limited or cancelled, so a later lookup
  /// can try again.
  func place(latitude: Double, longitude: Double) async throws -> Place?
}
