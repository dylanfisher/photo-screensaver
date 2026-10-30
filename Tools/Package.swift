// swift-tools-version:5.7
// Dev tools, kept out of the app's package so they never become app dependencies.
// Run through scripts/check: `swift run --package-path Tools swift-format …`.
import PackageDescription

let package = Package(
  name: "Tools",
  dependencies: [
    .package(url: "https://github.com/apple/swift-format.git", exact: "0.50700.1"),
  ]
)
