// swift-tools-version:5.7
// Tiers and their allowed imports: docs/map.md. Enforced by scripts/arch.
import PackageDescription

let package = Package(
  name: "photo-screensaver",
  platforms: [.macOS(.v12)],
  products: [.executable(name: "PhotoScreensaver", targets: ["App"])],
  targets: [
    .target(name: "Primitives"),
    .executableTarget(name: "App", dependencies: ["Primitives"]),
    .testTarget(name: "PrimitivesTests", dependencies: ["Primitives"]),
  ]
)
