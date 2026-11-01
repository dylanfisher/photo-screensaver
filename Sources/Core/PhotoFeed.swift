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
  /// Set when the error is that the timeframe in the settings has no photos.
  public var emptyTimeframe: Timeframe?
}

/// Hands out decoded photos in shuffled order, keeping up to `preloadCount` decoded ahead. One
/// loader decodes at a time, so a slow NAS read never has several full-size images in flight.
///
/// Shuffles the library's photo IDs rather than its rows, so a library of 100k photos costs
/// under a megabyte here, and looks up each photo's path as it's loaded. Reads the IDs again for
/// each pass, so a feed started while the first scan is still adding photos shows them too.
public actor PhotoFeed {
  /// Unreadable files in a row before giving up, e.g. because the share was unmounted.
  static let maxConsecutiveFailures = 20
  /// Files checked for orientation before deciding none match.
  static let maxOrientationChecks = 500

  private let library: PhotoLibrary
  private let root: URL
  /// This pass's photo IDs not shown yet, in shuffled order, next one last. Every photo is shown
  /// once before any repeats.
  private var pending: [Int64] = []
  /// The IDs the last pass read, shuffled again for a pass that a load starts after its first.
  private var passIDs: [Int64] = []
  /// Times the IDs were read from the database. Readable by tests.
  private(set) var idReads = 0
  private let settings: Settings
  private let screenPixels: CGSize
  private let log = Logger(subsystem: "com.dylanfisher.photo-screensaver", category: "feed")

  private var ready: [Photo] = []
  /// Readable by tests, to tell whether a load is under way.
  private(set) var loader: Task<Void, Never>?
  /// Set when a load fails; thrown by the next `next()`, which also allows a retry.
  private var failure: Error?
  private var waiters: [CheckedContinuation<Void, Error>] = []
  /// Bumped by `drop()`, so a load that finishes afterwards is discarded instead of buffered.
  private var generation = 0
  /// Calls to `photo(_:)` under way, which hold off new preloads.
  private(set) var revisits = 0

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

  /// Takes back a photo from `next()` that was never shown, so the next call hands it out
  /// instead of it being skipped this pass. Callers don't hand one back after `drop()`, which
  /// is meant to free decoded photos.
  public func putBack(_ photo: Photo) {
    ready.insert(photo, at: 0)
    wake(throwing: nil)
  }

  /// Decodes a photo shown before, for going back to it, without keeping it in the feed. Waits
  /// for a preload under way instead of decoding alongside it, and preloads wait for it.
  /// Doesn't check orientation, since the photo was shown once already. Preloading resumes
  /// afterwards unless `drop()` was called meanwhile, since then nothing is showing.
  public func photo(_ id: Int64) async throws -> Photo {
    let generation = generation
    revisits += 1
    let result: Result<Photo, Error>
    do {
      result = .success(try await revisit(id))
    } catch {
      result = .failure(error)
    }
    revisits -= 1
    if generation == self.generation { fill() }
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

  /// Picks up what a scan changed, starting a new pass. Photos already decoded are still shown.
  public func reload() {
    pending = []
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
    // Once per load: a few photos, none of them in the orientation setting, would otherwise
    // read every ID again for each pass through them.
    var mayReadIDs = true
    for _ in 0..<Self.maxOrientationChecks {
      // After `drop()`, stop instead of reading more files from the NAS.
      try Task.checkCancellation()
      let (next, readIDs) = try await nextPhoto(mayReadIDs: mayReadIDs)
      if readIDs { mayReadIDs = false }
      // Nil for a photo a scan removed since the IDs were read.
      guard let (id, url) = next else { continue }
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

  /// The next photo of this pass, starting a new pass when it's over, and whether that read
  /// the IDs from the database. A new pass reads them unless `mayReadIDs` is false, when it
  /// shuffles the last pass's again.
  private func nextPhoto(mayReadIDs: Bool) throws -> (photo: (Int64, URL)?, readIDs: Bool) {
    var readIDs = false
    if pending.isEmpty {
      if mayReadIDs || passIDs.isEmpty {
        // Worked out for each pass, so "on this day" moves on with the calendar, and a feed
        // started during the first scan takes in what it has added.
        let filter = CaptureFilter(settings.timeframe, today: Date(), calendar: .current)
        passIDs = try library.photoIDs(matching: filter)
        idReads += 1
        readIDs = true
        guard !passIDs.isEmpty else {
          let timeframe = filter == nil ? "" : " taken in \"\(settings.timeframe.title)\""
          throw FeedError(
            description: "no photos\(timeframe) in \(root.path)",
            emptyTimeframe: filter == nil ? nil : settings.timeframe)
        }
      }
      pending = passIDs.shuffled()
    }
    guard let id = pending.popLast() else {
      preconditionFailure("a pass with no photos throws above")
    }
    return (try library.photo(id).map { (id, root.appendingPathComponent($0.path)) }, readIDs)
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
