import Core
import XCTest

final class PlaceTests: XCTestCase {
  func testNeighborhoodCityAndCountry() {
    let place = Place(
      name: "2-chōme-21 Dōgenzaka", thoroughfare: "Dōgenzaka", subLocality: "Shibuya",
      locality: "Tokyo", administrativeArea: "Tokyo", country: "Japan")
    XCTAssertEqual(place.shortName, "Shibuya, Tokyo, Japan")
  }

  func testAnAreaOfInterestComesFirstAndTheStateStandsInForACity() {
    let place = Place(
      name: "Yosemite National Park", administrativeArea: "California", country: "United States",
      areasOfInterest: ["Yosemite National Park"])
    XCTAssertEqual(place.shortName, "Yosemite National Park, California, United States")
  }

  func testNeverAStreetAddress() {
    let place = Place(
      name: "1 Infinite Loop", thoroughfare: "Infinite Loop", locality: "Cupertino",
      administrativeArea: "CA", country: "United States")
    XCTAssertEqual(place.shortName, "Cupertino, United States")
    let unnamedStreet = Place(name: "350 5th Ave", locality: "New York", country: "United States")
    XCTAssertEqual(unnamedStreet.shortName, "New York, United States")
  }

  func testALandmarkNameIsKept() {
    let place = Place(
      name: "Golden Gate Bridge", locality: "San Francisco", country: "United States")
    XCTAssertEqual(place.shortName, "Golden Gate Bridge, San Francisco, United States")
  }

  func testRepeatsAreLeftOut() {
    let place = Place(name: "Singapore", locality: "Singapore", country: "Singapore")
    XCTAssertEqual(place.shortName, "Singapore")
  }

  func testWaterWhenThereIsNothingElse() {
    XCTAssertEqual(Place(ocean: "Pacific Ocean").shortName, "Pacific Ocean")
    XCTAssertEqual(
      Place(inlandWater: "Lake Tahoe", ocean: "Pacific Ocean").shortName, "Lake Tahoe")
    XCTAssertEqual(
      Place(country: "Greece", ocean: "Mediterranean Sea").shortName, "Greece")
  }

  func testNothingUsableIsNoName() {
    XCTAssertNil(Place().shortName)
    XCTAssertNil(Place(name: "  ", locality: "").shortName)
  }
}
