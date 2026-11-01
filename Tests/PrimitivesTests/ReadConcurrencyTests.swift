import Primitives
import XCTest

final class ReadConcurrencyTests: XCTestCase {
  func testClimbsToANASThatSaturatesAt12AndSettlesThere() {
    var controller = makeController()
    let levels = run(&controller, windows: 60, saturatesAt12)
    XCTAssertEqual(Array(levels.prefix(3)), [16, 32, 16])
    // Probes go one step either side and come back.
    XCTAssertTrue(levels.suffix(30).allSatisfy { (9...15).contains($0) }, "\(levels)")
    XCTAssertEqual(controller.trace, [16, 32, 16, 12])
  }

  func testFindsThePeakOfANASThatDegradesPast8() {
    var controller = makeController()
    let levels = run(&controller, windows: 60, degradesPast8)
    XCTAssertTrue(levels.suffix(30).allSatisfy { (7...11).contains($0) }, "\(levels)")
    XCTAssertEqual(controller.trace, [16, 32, 16, 12, 9])
  }

  func testNoisyMeasurementsStayNearTheBestLevel() {
    for seed: UInt64 in 1...20 {
      var noise = Noise(state: seed, spread: 0.15)
      var controller = makeController()
      let levels = run(&controller, windows: 200, noise: { noise.next() }, saturatesAt12)
      let late = levels.suffix(100)
      let mean = Double(late.reduce(0, +)) / Double(late.count)
      XCTAssertTrue((10...22).contains(mean), "seed \(seed): mean \(mean)")
      // Throughput within 10% of the best the NAS can do.
      let throughput = late.map(saturatesAt12).reduce(0, +) / Double(late.count)
      XCTAssertGreaterThan(throughput, 0.9 * saturatesAt12(12), "seed \(seed)")
    }
  }

  func testBacksOffWhenTheNASSlowsDown() {
    var controller = makeController()
    _ = run(&controller, windows: 40, saturatesAt12)
    XCTAssertEqual(controller.trace.last, 12)
    // Another client takes most of the NAS: it now serves 4 files at once, at 25 files/s each.
    let levels = run(&controller, windows: 60) { 25 * Double(min($0, 4)) }
    // The second held window after the slowdown halves the level; a probe may come first.
    XCTAssertTrue(levels.prefix(4).contains(6), "\(levels)")
    XCTAssertTrue(levels.suffix(30).allSatisfy { (3...5).contains($0) }, "\(levels)")
  }

  func testOneSlowWindowIsNotASlowdown() {
    var controller = makeController()
    _ = run(&controller, windows: 40, saturatesAt12)
    // To a window held at 12, between probes.
    while controller.phase != .holding(windowsLeft: 2, probeUp: false) || controller.level != 12 {
      _ = run(&controller, windows: 1, saturatesAt12)
    }
    let slower = ReadConcurrency.Window(filesPerSecond: 600, secondsPerFile: 0.1)
    controller.observe(slower)
    XCTAssertEqual(controller.level, 12)
    controller.observe(slower)
    XCTAssertEqual(controller.level, 6)
    XCTAssertEqual(controller.phase, .climbing(from: nil))
  }

  func testStaysInsideItsRange() {
    var linear = makeController()
    _ = run(&linear, windows: 60) { 50 * Double($0) }
    XCTAssertEqual(linear.level, 64)

    var flat = makeController()
    let levels = run(&flat, windows: 60) { _ in 100 }
    XCTAssertTrue(levels.allSatisfy { (2...64).contains($0) }, "\(levels)")
    XCTAssertEqual(flat.level, 2)

    var single = ReadConcurrency(range: 3...3, start: 8)
    XCTAssertTrue(run(&single, windows: 10, saturatesAt12).allSatisfy { $0 == 3 })
  }

  private func makeController() -> ReadConcurrency {
    ReadConcurrency(range: 2...64, start: 16)
  }

  /// Runs the controller for `windows` windows against a NAS whose throughput at each level is
  /// `filesPerSecond`, with each measurement scaled by `noise`. Returns the level of each window.
  private func run(
    _ controller: inout ReadConcurrency, windows: Int, noise: () -> Double = { 1 },
    _ filesPerSecond: (Int) -> Double
  ) -> [Int] {
    var levels: [Int] = []
    for _ in 0..<windows {
      let level = controller.level
      levels.append(level)
      let rate = filesPerSecond(level) * noise()
      // Little's law: with `level` files in flight, each takes level / rate seconds.
      controller.observe(.init(filesPerSecond: rate, secondsPerFile: Double(level) / rate))
    }
    return levels
  }
}

/// A NAS that serves 12 files at once, 50 files/s each, and queues the rest.
private func saturatesAt12(_ level: Int) -> Double { 50 * Double(min(level, 12)) }

/// A NAS whose disks thrash past 8 files at once.
private func degradesPast8(_ level: Int) -> Double {
  level <= 8 ? 50 * Double(level) : max(100, 400 - 30 * Double(level - 8))
}

/// A deterministic ±`spread` factor, so a failing run repeats.
private struct Noise {
  var state: UInt64
  let spread: Double

  mutating func next() -> Double {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    let unit = Double(state >> 11) / Double(1 << 53)
    return 1 + spread * (unit * 2 - 1)
  }
}
