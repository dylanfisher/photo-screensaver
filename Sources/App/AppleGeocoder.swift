import Core
import CoreLocation

/// Apple's reverse geocoder. It sends only the coordinates to Apple, needs no location
/// permission since it doesn't use the Mac's location, and is free but rate-limited per app,
/// so it's only asked about the photo on screen.
struct AppleGeocoder: Geocoder {
  func place(latitude: Double, longitude: Double) async throws -> Place? {
    // One geocoder per lookup: a CLGeocoder handles one request at a time, and cancelling
    // one lookup must not cancel another.
    let geocoder = CLGeocoder()
    let location = CLLocation(latitude: latitude, longitude: longitude)
    let placemarks: [CLPlacemark] = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
          if let error = error as? CLError, error.code == .geocodeFoundNoResult {
            continuation.resume(returning: [])
          } else if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: placemarks ?? [])
          }
        }
      }
    } onCancel: {
      // Calls the handler above with a cancellation error.
      geocoder.cancelGeocode()
    }
    guard let placemark = placemarks.first else { return nil }
    return Place(
      name: placemark.name, thoroughfare: placemark.thoroughfare,
      subLocality: placemark.subLocality, locality: placemark.locality,
      administrativeArea: placemark.administrativeArea, country: placemark.country,
      inlandWater: placemark.inlandWater, ocean: placemark.ocean,
      areasOfInterest: placemark.areasOfInterest ?? [])
  }
}
