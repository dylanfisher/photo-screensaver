import CoreGraphics
import Foundation
import Primitives
import Settings
import os

public struct Photo {
  /// The photo's ID in the library database.
  public let id: Int64
  public let url: URL
  public let image: CGImage

  public var size: CGSize { CGSize(width: image.width, height: image.height) }
}

public struct FeedError: Error, CustomStringConvertible {
  public let description: String
}

/// Hands out decoded photos in shuffled order, keeping up to `preloadCount` decoded ahead. One
/// loader decodes at a time, so a slow NAS read never has several full-size images in flight.
///
/// Shuffles the library's photo IDs rather than its rows, so a library of 100k photos costs
/// under a megabyte here, and looks up each photo's path as it's loaded.
public actor PhotoFeed {
  /// Unreadable files in a row before giving up, e.g. because the share was unmounted.
  static let maxConsecutiveFailures = 20
  /// Files checked for orientation before deciding none match.
  static let maxOrientationChecks = 500

  private let library: PhotoLibrary
  private let root: URL
  /// Nil until the IDs are first needed, and again after `reload()`.
  private var queue: ShuffleQueue<Int64>?
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
  /// Calls to `photo(_:)` under way, which hold off new preloads.
  private var revisits = 0

  /// Opens its own connection to the database at `databaseURL`, whose photos are in `root`.
  public init(databaseURL: URL, root: URL, settings: Settings, screenPixels: CGSize) throws {
    library = try PhotoLibrary(at: databaseURL)
    self.root = root
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

  /// Decodes a photo shown before, for going back to it, without keeping it in the feed. Waits
  /// for a preload under way instead of decoding alongside it, and preloads wait for it.
  /// Doesn't check orientation, since the photo was shown once already.
  public func photo(_ id: Int64) async throws -> Photo {
    revisits += 1
    let result: Result<Photo, Error>
    do {
      result = .success(try await revisit(id))
    } catch {
      result = .failure(error)
    }
    revisits -= 1
    fill()
    return try result.get()
  }

  private func revisit(_ id: Int64) async throws -> Photo {
    while let running = loader {
      await running.value
      try Task.checkCancellation()
    }
    try Task.checkCancellation()
    guard let path = try library.photo(id)?.path else {
      throw FeedError(description: "that photo is no longer in the library")
    }
    let url = root.appendingPathComponent(path)
    let decode = Task.detached { [settings, screenPixels] in
      try Self.decode(id, url, settings: settings, screenPixels: screenPixels, anyOrientation: true)
    }
    // As the loader, it keeps `fill()` and other revisits from decoding at the same time.
    loader = Task { _ = await decode.result }
    defer { loader = nil }
    guard let photo = try await decode.value else {
      preconditionFailure("decoding in any orientation always gives a photo")
    }
    return photo
  }

  /// Picks up what a scan changed, starting a new shuffle. Photos already decoded are still
  /// shown.
  public func reload() {
    queue = nil
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
    guard loader == nil, revisits == 0, failure == nil, ready.count < settings.preloadCount
    else { return }
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
      // Nil for a photo a scan removed since the IDs were read.
      guard let (id, url) = try await nextPhoto() else { continue }
      do {
        if let photo = try Self.decode(
          id, url, settings: settings, screenPixels: screenPixels, anyOrientation: false)
        {
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

  private func nextPhoto() throws -> (Int64, URL)? {
    var queue = try self.queue ?? ShuffleQueue(library.photoIDs())
    defer { self.queue = queue }
    guard let id = queue.next() else {
      throw FeedError(description: "no photos in \(root.path)")
    }
    return try library.photo(id).map { (id, root.appendingPathComponent($0.path)) }
  }

  /// Nil when the photo doesn't match the orientation setting.
  private static func decode(
    _ id: Int64, _ url: URL, settings: Settings, screenPixels: CGSize, anyOrientation: Bool
  ) throws -> Photo? {
    // ImageIO autoreleases objects that hold the full decoded pixels, and Swift concurrency's
    // threads never drain an autorelease pool, so without this every photo stays in memory.
    try autoreleasepool {
      try decodeUnpooled(
        id, url, settings: settings, screenPixels: screenPixels, anyOrientation: anyOrientation)
    }
  }

  private static func decodeUnpooled(
    _ id: Int64, _ url: URL, settings: Settings, screenPixels: CGSize, anyOrientation: Bool
  ) throws -> Photo? {
    let file = try ImageFile(url: url)
    let size = try file.displaySize()
    switch settings.orientation {
    case .landscape where !anyOrientation && size.width < size.height: return nil
    case .portrait where !anyOrientation && size.width > size.height: return nil
    default: break
    }
    let edge = decodeLongEdge(
      photo: size, screenPixels: screenPixels, scaling: settings.scaling,
      zoom: settings.kenBurns ? KenBurns.maxScale : 1)
    return Photo(id: id, url: url, image: try file.decode(maxPixelSize: edge))
  }
}
