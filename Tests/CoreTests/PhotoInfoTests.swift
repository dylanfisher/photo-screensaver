import XCTest

@testable import Core

final class PhotoInfoTests: XCTestCase {
  private let britain = Locale(identifier: "en_GB")

  private func metadata(
    width: Int = 6000, height: Int = 4000, _ change: (inout PhotoMetadata) -> Void = { _ in }
  ) -> PhotoMetadata {
    var metadata = PhotoMetadata(width: width, height: height)
    change(&metadata)
    return metadata
  }

  func testEveryField() {
    let full = metadata {
      $0.takenAt = "2014-06-14 18:32:05"
      $0.make = "Canon"
      $0.model = "Canon EOS 5D Mark III"
      $0.lens = "EF24-70mm f/2.8L II USM"
      $0.fNumber = 2.8
      $0.exposure = 0.004
      $0.iso = 400
      $0.focalLength = 35
      $0.focalLength35mm = 35
      $0.latitude = 35.65949
      $0.longitude = 139.70051
    }
    let info = PhotoInfo(
      path: "2014/Japan trip/IMG_1234.JPG", metadata: full, place: "Shibuya, Tokyo, Japan",
      locale: britain)
    XCTAssertEqual(info.headlines.count, 2)
    XCTAssertEqual(info.headlines[0], "Shibuya, Tokyo, Japan")
    XCTAssertEqual(
      info.details,
      [
        "Canon EOS 5D Mark III", "EF24-70mm f/2.8L II USM", "ƒ/2.8 · 1/250 s · ISO 400 · 35 mm",
        "24 MP · 6000 × 4000", "Japan trip / IMG_1234.JPG",
      ])
  }

  func testCoordinatesUntilThePlaceIsKnown() {
    let located = metadata {
      $0.latitude = 35.65949
      $0.longitude = 139.70051
    }
    let info = PhotoInfo(path: "a.jpg", metadata: located, place: nil, locale: britain)
    XCTAssertEqual(info.headlines, ["35.6595° N, 139.7005° E"])
    XCTAssertEqual(
      PhotoInfo.coordinates(latitude: -33.8568, longitude: -70.6483), "33.8568° S, 70.6483° W")
  }

  func testAPhotoWithoutDetailsShowsItsFileName() {
    let info = PhotoInfo(path: "Holidays/a.jpg", metadata: nil, place: nil, locale: britain)
    XCTAssertEqual(info.headlines, [])
    XCTAssertEqual(info.details, ["Holidays / a.jpg"])
    XCTAssertEqual(PhotoInfo.file("a.jpg"), "a.jpg")
    XCTAssertEqual(PhotoInfo.file("2014/06/Trip/a.jpg"), "Trip / a.jpg")
  }

  func testMissingFieldsAreLeftOut() {
    let info = PhotoInfo(path: "a.jpg", metadata: metadata(), place: "Ignored", locale: britain)
    XCTAssertEqual(info.headlines, [], "a place name without coordinates isn't this photo's")
    XCTAssertEqual(info.details, ["24 MP · 6000 × 4000", "a.jpg"])
  }

  func testDateIsTheCameraClockInTheLocalesWords() throws {
    let date = try XCTUnwrap(PhotoInfo.date("2014-06-14 18:32:05", offset: nil, locale: britain))
    // ICU's exact punctuation differs between macOS versions, so check the parts.
    for part in ["Saturday", "14 June 2014", "18:32"] {
      XCTAssertTrue(date.contains(part), date)
    }
    XCTAssertFalse(date.contains("GMT"), date)
    let american = try XCTUnwrap(
      PhotoInfo.date("2014-06-14 18:32:05", offset: nil, locale: Locale(identifier: "en_US")))
    XCTAssertTrue(american.contains("June 14, 2014"), american)
    XCTAssertTrue(american.contains("6:32"), american)
  }

  func testAnOffsetNamesTheZoneWithoutMovingTheTime() throws {
    let date = try XCTUnwrap(
      PhotoInfo.date("2021-07-04 18:30:00", offset: "-04:00", locale: britain))
    XCTAssertTrue(date.contains("Sunday"), date)
    XCTAssertTrue(date.contains("18:30"), date)
    XCTAssertTrue(date.contains("GMT-4"), date)
    let india = try XCTUnwrap(
      PhotoInfo.date("2021-07-04 23:45:00", offset: "+05:30", locale: britain))
    XCTAssertTrue(india.contains("4 July 2021"), india)
    XCTAssertTrue(india.contains("23:45"), india)
  }

  func testABadDateIsLeftOut() {
    XCTAssertNil(PhotoInfo.date("2014-06-14", offset: nil, locale: britain))
  }

  func testCameraNamesTheMakeOnce() {
    XCTAssertEqual(
      PhotoInfo.camera(make: "Canon", model: "Canon EOS 5D Mark III"), "Canon EOS 5D Mark III")
    XCTAssertEqual(PhotoInfo.camera(make: "NIKON CORPORATION", model: "NIKON D750"), "NIKON D750")
    XCTAssertEqual(
      PhotoInfo.camera(make: "EASTMAN KODAK COMPANY", model: "KODAK Z990"), "KODAK Z990")
    XCTAssertEqual(PhotoInfo.camera(make: "Apple", model: "iPhone 12"), "Apple iPhone 12")
    XCTAssertEqual(PhotoInfo.camera(make: "SONY", model: "ILCE-7M3"), "SONY ILCE-7M3")
    XCTAssertEqual(PhotoInfo.camera(make: "OLYMPUS IMAGING CORP.", model: "E-M5"), "OLYMPUS E-M5")
    XCTAssertEqual(
      PhotoInfo.camera(make: "RICOH IMAGING COMPANY, LTD.", model: "PENTAX K-3"),
      "RICOH PENTAX K-3")
    XCTAssertEqual(PhotoInfo.camera(make: "FUJIFILM", model: nil), "FUJIFILM")
    XCTAssertEqual(PhotoInfo.camera(make: nil, model: "X100V"), "X100V")
    XCTAssertNil(PhotoInfo.camera(make: nil, model: nil))
  }

  func testALensThatRepeatsTheCameraIsLeftOut() {
    let phone = metadata {
      $0.model = "DMC-LX7"
      $0.lens = "DMC-LX7"
    }
    XCTAssertEqual(
      PhotoInfo(path: "a.jpg", metadata: phone, place: nil, locale: britain).details,
      ["DMC-LX7", "24 MP · 6000 × 4000", "a.jpg"])
  }

  func testExposure() {
    XCTAssertEqual(
      PhotoInfo.exposure(
        metadata {
          $0.fNumber = 1.6
          $0.exposure = 1 / 60
          $0.iso = 32
          $0.focalLength = 4.2
          $0.focalLength35mm = 26
        }), "ƒ/1.6 · 1/60 s · ISO 32 · 4.2 mm (26 mm equiv.)")
    XCTAssertEqual(
      PhotoInfo.exposure(
        metadata {
          $0.fNumber = 8
          $0.exposure = 2
        }), "ƒ/8 · 2 s")
    XCTAssertEqual(PhotoInfo.exposure(metadata { $0.exposure = 0.5 }), "0.5 s")
    XCTAssertEqual(PhotoInfo.exposure(metadata { $0.exposure = 1 / 3 }), "1/3 s")
    XCTAssertEqual(PhotoInfo.exposure(metadata { $0.focalLength35mm = 28 }), "28 mm equiv.")
    XCTAssertEqual(
      PhotoInfo.exposure(
        metadata {
          $0.focalLength = 50
          $0.focalLength35mm = 50
        }), "50 mm")
  }

  func testZeroValuesFromManualLensesAreLeftOut() {
    XCTAssertNil(
      PhotoInfo.exposure(
        metadata {
          $0.fNumber = 0
          $0.focalLength = 0
          $0.iso = 0
        }))
  }

  func testDimensions() {
    XCTAssertEqual(PhotoInfo.dimensions(width: 4032, height: 3024), "12.2 MP · 4032 × 3024")
    XCTAssertEqual(PhotoInfo.dimensions(width: 30, height: 20), "30 × 20")
  }
}
