import Darwin
import Foundation
import Primitives
import os

/// A photo file the walk found, with its size and mtime from the directory listing.
struct WalkedFile: Equatable {
  /// Relative to the library folder.
  var path: String
  var size: Int
  var mtime: Double
}

/// Brings the library database in line with the library folder, and reads the details of every
/// photo that hasn't had them read. Incremental on (path, size, mtime), so a rescan with no
/// changes reads no file. Photo files are only ever opened read-only, by `PhotoMetadata.read`.
///
/// Listers walk the folder depth-first and add each folder's new and changed files to the
/// database as they go; readers take unread rows from the database in ID order, which is the
/// order they were added, while the walk runs (ADR 0005). On a network volume `ReadConcurrency`
/// sets how many read at once.
///
/// A missing or vanished library folder removes nothing, and neither does a library folder that
/// lists nothing while the database has photos from it. Nothing is removed under a folder that
/// can't be listed, or one that lists nothing while the database has photos under it, since an
/// SMB hiccup can make a folder look empty.
///
/// `@unchecked Sendable` because its threads share the state below through two locks, which
/// Swift 5.7 has no checked type for: `condition` guards every `var`, and `storeLock` guards
/// `library`, the one connection the threads share. `storeLock` is never taken while holding
/// `condition`, so a store or a fetch doesn't stall the walk.
public final class LibraryScan: @unchecked Sendable {
  public static let extensions: Set<String> = [
    "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff",
  ]
  /// System folders a NAS keeps inside shares: Synology thumbnails, recycle bin and snapshots.
  static let skippedFolders: Set<String> = ["@eaDir", "#recycle", "#snapshot"]
  /// Folders listed at once. A listing is a round trip or two that yields several photos, each
  /// of which costs a round trip or two to read, so a few listers stay ahead of the readers
  /// without crowding the NAS with directory requests.
  static let listers = 4
  /// Files read at once on a local disk, where parsing, not waiting, is the cost.
  static let localReaders = ProcessInfo.processInfo.activeProcessorCount
  /// Files read at once on a network volume: where tuning starts, and how far it may go. The
  /// top is half of music-player's, since the slideshow reads full photos from the same share.
  static let networkReaders = 2...32
  static let networkStart = 16
  /// A throughput window closes once it's at least this long and each reader has finished
  /// `windowFilesPerReader` files in it, so a few slow files don't decide the level.
  static let windowSeconds = 2.0
  static let windowFilesPerReader = 4
  /// Results stored per transaction, and unread rows taken from the database at a time.
  static let batchSize = 200
  static let fetchSize = 256
  static let progressSeconds = 1.0

  /// Where the scan has got to. Published at most once every `progressSeconds`.
  public struct Progress: Equatable, Sendable {
    /// Photo files the walk has listed so far.
    public var found = 0
    public var walkFinished = false
    /// Rows in the database, and those whose details aren't read yet.
    public var photos = 0
    public var unread = 0
  }

  public struct Summary: Equatable, Sendable {
    public var found = 0
    /// Files whose details were read, including those with no image in them.
    public var read = 0
    /// Files that couldn't be read. They stay unread, so the next scan tries them again.
    public var failed = 0
    public var removed = 0
    /// Folders and entries the walk couldn't read, and folders that listed nothing while the
    /// database had photos under them. Nothing under them was removed.
    public var unreadable = 0
    /// The folder listed nothing while the database had photos from it, so none were removed.
    public var listedNothing = false
    public var cancelled = false
    /// Each reader count settled on, for a network volume.
    public var readerTrace: [Int] = []
  }

  private let databaseURL: URL
  private let root: String
  private let progress: AsyncStream<Progress>.Continuation?
  private let threads = DispatchGroup()
  private let log = Logger(subsystem: "com.dylanfisher.photo-screensaver", category: "scan")

  /// Results are also stored once the oldest waiting one is this old, so at NAS speed, where 200
  /// results take most of a minute, quitting loses little and progress keeps up. A variable so
  /// tests can store every result at once.
  var batchSeconds = 3.0
  /// Called by a lister after it records each folder, with the folder's path. For tests.
  var didList: ((String) -> Void)?
  /// For tests, which can't move a folder to another volume.
  var deviceOf: (String) -> dev_t? = directoryDevice

  private let storeLock = NSLock()
  private var library: PhotoLibrary?

  private let condition = NSCondition()
  private var summary = Summary()
  private var device: dev_t = 0
  /// Rows by path; the walk takes out each one it lists, so what's left at the end is gone.
  private var known: [String: WalkedFile] = [:]
  private var knownAtStart = 0
  /// Folders still to list, relative to `root` ("" is `root`), popped from the end.
  private var directories = [""]
  private var listing = 0
  private var unreadablePaths: Set<String> = []
  /// Folders other than `root` that listed no entries.
  private var emptyFolders: Set<String> = []
  private var rootEntries: Int?
  private var rootError: String?
  private var walkFinished = false
  /// Bumped after each commit of new rows, so readers know to look for them.
  private var walkCommits = 0
  /// Unread rows taken from the database, next one last.
  private var queued: [(id: Int64, path: String)] = []
  private var cursor: Int64 = 0
  private var fetching = false
  /// The last fetch found every unread row after `cursor`, as of `commitsAtFetch`.
  private var exhausted = false
  private var commitsAtFetch = -1
  private var limit = 1
  private var readerThreads = 0
  private var controller: ReadConcurrency?
  private var window = Window(start: 0)
  private var batch: [(id: Int64, metadata: PhotoMetadata?)] = []
  /// Uptime when the oldest result in `batch` was added.
  private var batchStarted: UInt64 = 0
  private var storeError: Error?
  private var rootLost = false
  private var lastPublished: UInt64 = 0

  /// Files finished since `start`, and whether a reader waited for the walk during it, which
  /// makes its throughput say nothing about the NAS: more readers can't read files the walk
  /// hasn't found.
  private struct Window {
    var start: UInt64
    var files = 0
    var seconds = 0.0
    var starved = false
  }

  /// Scans `root` into the database at `databaseURL`, which must already be in use for it
  /// (`PhotoLibrary.use(root:)`).
  public init(
    databaseURL: URL, root: URL, progress: AsyncStream<Progress>.Continuation? = nil
  ) {
    self.databaseURL = databaseURL
    self.root = PhotoLibrary.path(of: root)
    self.progress = progress
  }

  /// Blocks until the walk has finished and every unread photo has been tried, or the scan is
  /// cancelled, so call it off the main thread and outside Swift concurrency's threads. Throws
  /// when the folder is missing, unreadable or goes away, or the database fails. Call it once.
  public func run() throws -> Summary {
    defer { progress?.finish() }
    guard let device = deviceOf(root) else {
      throw LibraryError(description: "library folder not found: \(root)")
    }
    let library = try PhotoLibrary(at: databaseURL)
    guard try library.root() == root else {
      throw LibraryError(description: "the library database isn't set up for \(root)")
    }
    let known = try library.knownFiles()
    let isLocal: Bool
    do {
      // Nil only where the volume doesn't say. Reading it as a network volume is the safe
      // guess, since that only means tuning the readers.
      isLocal =
        try URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal
        ?? false
    } catch {
      isLocal = false
      log.error(
        "can't tell whether \(self.root, privacy: .public) is local: \(String(describing: error))")
    }
    let controller =
      isLocal ? nil : ReadConcurrency(range: Self.networkReaders, start: Self.networkStart)

    condition.locking {
      self.device = device
      self.library = library
      self.known = known
      knownAtStart = known.count
      self.controller = controller
      window = Window(start: DispatchTime.now().uptimeNanoseconds)
      for _ in 0..<Self.listers { spawn { self.lister() } }
      setLimit(controller?.level ?? Self.localReaders)
    }
    threads.wait()

    // Every thread has finished, so nothing else uses `library` or the state now.
    if storeError == nil, !batch.isEmpty { store(batch) }
    publish(force: true)
    if let rootError {
      throw LibraryError(description: "can't read library folder \(root): \(rootError)")
    }
    if let storeError { throw storeError }
    if rootLost {
      throw LibraryError(
        description: "library folder \(root) went away during the scan; kept every photo")
    }
    summary.readerTrace = self.controller?.trace ?? []
    return summary
  }

  /// Stops listers and readers at their next folder or file. What they've stored is kept, and
  /// nothing is removed.
  public func cancel() {
    condition.locking {
      summary.cancelled = true
      condition.broadcast()
    }
  }

  // MARK: Walking

  private func lister() {
    while let directory = nextDirectory() {
      // Foundation autoreleases each listing's URLs, and these threads have no pool of their own
      // to drain them.
      let listed = autoreleasepool { list(directory) }
      let changed = condition.locking { add(listed, of: directory) }
      if !changed.isEmpty { store { try $0.insert(changed, root: root) } }
      didList?(directory)
      let last = condition.locking { () -> Bool in
        listing -= 1
        if !changed.isEmpty { walkCommits += 1 }
        condition.broadcast()
        return directories.isEmpty && listing == 0 && !stopped
      }
      if last { finishWalk() }
      publish()
    }
  }

  private func nextDirectory() -> String? {
    condition.locking {
      while directories.isEmpty && listing > 0 && !stopped { condition.wait() }
      guard !stopped, let directory = directories.popLast() else { return nil }
      listing += 1
      return directory
    }
  }

  /// Records a listing and returns its new and changed files. Called with `condition` held.
  private func add(_ listed: Listing, of directory: String) -> [WalkedFile] {
    if directory.isEmpty {
      rootEntries = listed.entries
      rootError = listed.error
    }
    unreadablePaths.formUnion(listed.unreadable)
    if !directory.isEmpty, listed.error == nil, listed.entries == 0 {
      emptyFolders.insert(directory)
    }
    summary.unreadable += listed.unreadable.count
    directories += listed.directories.reversed()
    summary.found += listed.files.count
    return listed.files.filter { file in known.removeValue(forKey: file.path) != file }
  }

  /// Run by the lister that lists the last folder: removes the rows of files that are gone, if
  /// it's safe to.
  private func finishWalk() {
    // Outside `condition`: on a hung SMB mount the stat blocks, and readers and `cancel()` need
    // the lock meanwhile. `device` is only written before the threads start.
    let sameDevice = deviceOf(root) == device
    let gone = condition.locking { () -> [String] in
      if !sameDevice {
        rootLost = true
        condition.broadcast()
        return []
      }
      if rootEntries == 0 && knownAtStart > 0 {
        summary.listedNothing = true
        return []
      }
      var gone: [String] = []
      var keptEmpty: Set<String> = []
      for path in known.keys where Self.folder(containing: path, in: unreadablePaths) == nil {
        if let empty = Self.folder(containing: path, in: emptyFolders) {
          keptEmpty.insert(empty)
        } else {
          gone.append(path)
        }
      }
      summary.unreadable += keptEmpty.count
      return gone
    }
    if !gone.isEmpty { store { try $0.remove(gone, root: root) } }
    condition.locking {
      if storeError == nil { summary.removed = gone.count }
      known = [:]
      walkFinished = true
      condition.broadcast()
    }
    publish(force: true)
  }

  /// `path` itself or the folder above it that's in `folders`, if any. Looks up each ancestor
  /// rather than comparing prefixes, so a walk that removes many files with many unreadable
  /// folders doesn't hold `condition` for long.
  static func folder(containing path: String, in folders: Set<String>) -> String? {
    guard !folders.isEmpty else { return nil }
    var candidate = Substring(path)
    while true {
      if folders.contains(String(candidate)) { return String(candidate) }
      guard let slash = candidate.lastIndex(of: "/") else { return nil }
      candidate = candidate[..<slash]
    }
  }

  private struct Listing {
    var files: [WalkedFile] = []
    /// Subfolders to walk, in listing order.
    var directories: [String] = []
    var unreadable: [String] = []
    /// Every entry listed, to tell an empty mount point from a library.
    var entries = 0
    /// Why the folder couldn't be listed.
    var error: String?
  }

  private static let keys: [URLResourceKey] = [
    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey,
    .contentModificationDateKey,
  ]

  /// Lists `directory`, skipping hidden entries such as `.DS_Store` and the `._` files macOS
  /// leaves on SMB shares. `contentsOfDirectory` fetches the keys in bulk with the listing, so a
  /// folder costs a round trip per batch of entries rather than one per file.
  private func list(_ directory: String) -> Listing {
    var result = Listing()
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: absolute(directory), isDirectory: true),
        includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles])
    } catch {
      result.unreadable.append(directory)
      result.error = "\(error)"
      return result
    }
    result.entries = entries.count
    for entry in entries {
      let name = entry.lastPathComponent
      // Built from `directory`, not `entry.path`, so every path keeps the root's spelling even
      // where Foundation would resolve a symbolic link such as /var.
      let path = directory.isEmpty ? name : directory + "/" + name
      let values: URLResourceValues
      do {
        values = try entry.resourceValues(forKeys: Set(Self.keys))
      } catch {
        result.unreadable.append(path)
        continue
      }
      if values.isDirectory == true {
        guard values.isSymbolicLink != true, values.isPackage != true,
          !Self.skippedFolders.contains(name)
        else { continue }
        result.directories.append(path)
      } else if values.isRegularFile == true,
        Self.extensions.contains(entry.pathExtension.lowercased())
      {
        guard let size = values.fileSize, let modified = values.contentModificationDate else {
          result.unreadable.append(path)
          continue
        }
        result.files.append(
          WalkedFile(path: path, size: size, mtime: modified.timeIntervalSince1970))
      }
    }
    return result
  }

  private func absolute(_ path: String) -> String {
    path.isEmpty ? root : root + "/" + path
  }

  // MARK: Reading

  private func reader() {
    while let photo = nextPhoto() {
      let started = DispatchTime.now().uptimeNanoseconds
      let url = URL(fileURLWithPath: absolute(photo.path))
      var metadata: PhotoMetadata?
      var failure: PhotoMetadataError?
      // ImageIO autoreleases its sources, and these threads have no pool of their own.
      autoreleasepool {
        do {
          metadata = try PhotoMetadata.read(at: url)
        } catch let error as PhotoMetadataError {
          failure = error
        } catch {
          failure = PhotoMetadataError(kind: .unreadable, description: "\(error)")
        }
      }
      if let failure, failure.kind == .unreadable, deviceOf(root) != device {
        condition.locking {
          readerThreads -= 1
          rootLost = true
          condition.broadcast()
        }
        return
      }
      let seconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
      let full = condition.locking { () -> [(id: Int64, metadata: PhotoMetadata?)]? in
        if let failure, failure.kind == .unreadable {
          summary.failed += 1
          log.error("can't read \(photo.path, privacy: .public): \(failure.description)")
        } else {
          summary.read += 1
          if batch.isEmpty { batchStarted = DispatchTime.now().uptimeNanoseconds }
          batch.append((photo.id, metadata))
        }
        measure(seconds)
        let age = Double(DispatchTime.now().uptimeNanoseconds - batchStarted) / 1e9
        guard batch.count >= Self.batchSize || (!batch.isEmpty && age >= batchSeconds) else {
          return nil
        }
        defer { batch = [] }
        return batch
      }
      if let full { store(full) }
      publish()
    }
  }

  /// The next unread row, or nil when this reader should stop, which it has then been counted
  /// as doing.
  private func nextPhoto() -> (id: Int64, path: String)? {
    condition.lock()
    defer { condition.unlock() }
    while !stopped && readerThreads <= limit {
      if let photo = queued.popLast() { return photo }
      if fetching {
        condition.wait()
        continue
      }
      if exhausted && commitsAtFetch == walkCommits {
        if walkFinished { break }
        window.starved = true
        condition.wait()
        continue
      }
      // Fetched outside `condition`, so the walk and the other readers carry on meanwhile.
      fetching = true
      let after = cursor
      let commits = walkCommits
      condition.unlock()
      let rows = withLibrary { try $0.unread(after: after, limit: Self.fetchSize) }
      condition.lock()
      fetching = false
      commitsAtFetch = commits
      exhausted = (rows?.count ?? 0) < Self.fetchSize
      if let last = rows?.last { cursor = last.id }
      queued = (rows ?? []).reversed()
      condition.broadcast()
    }
    readerThreads -= 1
    return nil
  }

  /// Adds a finished file to the window, and when the window closes, lets the controller pick
  /// the next level. Called with `condition` held.
  private func measure(_ seconds: Double) {
    guard var tuning = controller else { return }
    window.files += 1
    window.seconds += seconds
    let now = DispatchTime.now().uptimeNanoseconds
    let elapsed = Double(now - window.start) / 1e9
    guard elapsed >= Self.windowSeconds, window.files >= Self.windowFilesPerReader * limit else {
      return
    }
    if !window.starved {
      tuning.observe(
        ReadConcurrency.Window(
          filesPerSecond: Double(window.files) / elapsed,
          secondsPerFile: window.seconds / Double(window.files)))
      controller = tuning
      setLimit(tuning.level)
    }
    window = Window(start: now)
  }

  /// Starts readers until `limit` run. Readers above a lowered limit stop at their next file.
  /// Called with `condition` held.
  private func setLimit(_ level: Int) {
    limit = level
    while !stopped && readerThreads < limit {
      readerThreads += 1
      spawn { self.reader() }
    }
    condition.broadcast()
  }

  // MARK: Shared

  private func store(_ results: [(id: Int64, metadata: PhotoMetadata?)]) {
    store { try $0.store(results, root: root) }
  }

  private func store(_ write: (PhotoLibrary) throws -> Void) {
    _ = withLibrary(write)
  }

  /// Runs `body` on the shared connection. A failure stops the scan and `run` throws it.
  private func withLibrary<T>(_ body: (PhotoLibrary) throws -> T) -> T? {
    storeLock.locking {
      guard condition.locking({ storeError == nil }), let library else { return nil }
      do {
        return try body(library)
      } catch {
        condition.locking {
          storeError = error
          condition.broadcast()
        }
        return nil
      }
    }
  }

  /// Publishes progress if `progressSeconds` have passed since the last time, or `force`. Under
  /// `storeLock`, so values go out in order.
  private func publish(force: Bool = false) {
    guard let progress else { return }
    storeLock.locking {
      let now = DispatchTime.now().uptimeNanoseconds
      let due = condition.locking { () -> Bool in
        guard force || Double(now - lastPublished) / 1e9 >= Self.progressSeconds else {
          return false
        }
        lastPublished = now
        return true
      }
      guard due, condition.locking({ storeError == nil }), let library else { return }
      let counts: (photos: Int, unread: Int)
      do {
        counts = try library.counts()
      } catch {
        condition.locking {
          storeError = error
          condition.broadcast()
        }
        return
      }
      progress.yield(
        condition.locking {
          Progress(
            found: summary.found, walkFinished: walkFinished, photos: counts.photos,
            unread: counts.unread)
        })
    }
  }

  private func spawn(_ body: @escaping @Sendable () -> Void) {
    threads.enter()
    let thread = Thread { [threads] in
      body()
      threads.leave()
    }
    thread.qualityOfService = .utility
    thread.start()
  }

  /// Called with `condition` held.
  private var stopped: Bool {
    summary.cancelled || rootLost || rootError != nil || storeError != nil
  }
}

/// The device of the directory at `path`, or nil when it's missing or not a directory. A NAS
/// unmounted mid-scan leaves its mount point on the startup disk's device, or gone.
private func directoryDevice(_ path: String) -> dev_t? {
  var info = stat()
  guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
  return info.st_dev
}

extension NSLocking {
  /// Foundation's own `withLock` is newer than macOS 12.
  fileprivate func locking<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
