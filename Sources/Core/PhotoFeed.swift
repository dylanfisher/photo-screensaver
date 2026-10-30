import CoreGraphics
import Foundation
import Primitives
import Settings
import os

public struct Photo {
  public let url: URL
  public let image: CGImage

  public var size: CGSize { CGSize(width: image.width, height: image.height) }
}

public struct FeedError: Error, CustomStringConvertible {
  public let description: String
}

/// Hands out decoded photos in shuffled order, keeping up to `preloadCount` decoded ahead. One
/// loader decodes at a time, so a slow NAS read never has several full-size images in flight.
public actor PhotoFeed {
  /// Unreadable files in a row before giving up, e.g. because the share was unmounted.
  static let maxConsecutiveFailures = 20
  /// Files checked for orientation before deciding none match.
  static let maxOrientationChecks = 500

  private var index: PhotoIndex
  private var queue: ShuffleQueue<String>
  private let settings: Settings
  private let screenPixels: CGSize
  private let log = Logger(subsystem: "com.dylanfisher.photo-screensaver", category: "feed")

  private var ready: [Photo] = []
  private var loader: Task<Void, Never>?
  /// Set when a load fails; thrown by the next `next()`, which also allows a retry.
  private var failure: Error?
  private var waiters: [CheckedContinuation<Void, Error>] = []
  /// Bumped by `drop()`, so a load that finishes afterwards is discarded instead of buffered.
  private var generation = 0

  public init(index: PhotoIndex, settings: Settings, screenPixels: CGSize) {
    self.index = index
    self.queue = ShuffleQueue(index.paths)
    self.settings = settings
    self.screenPixels = screenPixels
  }

  /// Throws `CancellationError` if `drop()` is called while waiting.
  public func next() async throws -> Photo {
    while ready.isEmpty {
      if let failure {
        self.failure = nil
        throw failure
      }
      fill()
      try await withCheckedThrowingContinuation { waiters.append($0) }
      // A cancelled caller must not take a photo meant for whoever asks next.
      try Task.checkCancellation()
    }
    let photo = ready.removeFirst()
    fill()
    return photo
  }

  /// Swaps in a fresh scan. Photos already decoded are still shown.
  public func replace(_ index: PhotoIndex) {
    self.index = index
    queue = ShuffleQueue(index.paths)
  }

  /// Frees decoded photos, which can be hundreds of MB, e.g. while the display is off.
  public func drop() {
    generation += 1
    // `loader` stays set until the cancelled load finishes, so a new one can't start
    // alongside it and put two full-size decodes in memory.
    loader?.cancel()
    ready.removeAll()
    failure = nil
    wake(throwing: CancellationError())
  }

  private func fill() {
    guard loader == nil, failure == nil, ready.count < settings.preloadCount else { return }
    let generation = generation
    loader = Task.detached { [self] in
      let result: Result<Photo, Error>
      do {
        result = .success(try await load())
      } catch {
        result = .failure(error)
      }
      await finish(result, generation: generation)
    }
  }

  private func finish(_ result: Result<Photo, Error>, generation: Int) {
    loader = nil
    guard generation == self.generation else {
      // Dropped while loading; start over for anyone who asked since.
      if !waiters.isEmpty { fill() }
      return
    }
    switch result {
    case .success(let photo): ready.append(photo)
    case .failure(let error): failure = error
    }
    wake(throwing: nil)
    fill()
  }

  private func wake(throwing error: Error?) {
    let waiting = waiters
    waiters = []
    for waiter in waiting {
      if let error { waiter.resume(throwing: error) } else { waiter.resume() }
    }
  }

  /// Nonisolated so decoding runs off the actor and never blocks `next()`.
  private nonisolated func load() async throws -> Photo {
    var failures = 0
    for _ in 0..<Self.maxOrientationChecks {
      // After `drop()`, stop instead of reading more files from the NAS.
      try Task.checkCancellation()
      let url = try await nextURL()
      do {
        if let photo = try Self.decode(url, settings: settings, screenPixels: screenPixels) {
          return photo
        }
      } catch {
        log.error("skipping \(url.path, privacy: .public): \(String(describing: error))")
        failures += 1
        if failures >= Self.maxConsecutiveFailures {
          throw FeedError(
            description: "\(failures) photos in a row failed to load; last: \(error)")
        }
      }
    }
    throw FeedError(
      description:
        "no \(settings.orientation.rawValue) photos in \(Self.maxOrientationChecks) checked")
  }

  private func nextURL() throws -> URL {
    guard let path = queue.next() else {
      throw FeedError(description: "no photos in \(index.root)")
    }
    return index.url(for: path)
  }

  /// Nil when the photo doesn't match the orientation setting.
  private static func decode(
    _ url: URL, settings: Settings, screenPixels: CGSize
  ) throws -> Photo? {
    // ImageIO autoreleases objects that hold the full decoded pixels, and Swift concurrency's
    // threads never drain an autorelease pool, so without this every photo stays in memory.
    try autoreleasepool { try decodeUnpooled(url, settings: settings, screenPixels: screenPixels) }
  }

  private static func decodeUnpooled(
    _ url: URL, settings: Settings, screenPixels: CGSize
  ) throws -> Photo? {
    let file = try ImageFile(url: url)
    let size = try file.displaySize()
    switch settings.orientation {
    case .landscape where size.width < size.height: return nil
    case .portrait where size.width > size.height: return nil
    default: break
    }
    let edge = decodeLongEdge(
      photo: size, screenPixels: screenPixels, scaling: settings.scaling,
      zoom: settings.kenBurns ? KenBurns.maxScale : 1)
    return Photo(url: url, image: try file.decode(maxPixelSize: edge))
  }
}
