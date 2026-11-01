import Foundation
import Primitives
import os

public struct LibraryError: Error, CustomStringConvertible {
  public let description: String
}

/// A calendar month, for choosing photos by when they were taken.
public struct CaptureMonth: Comparable, Hashable, Sendable {
  public let year: Int
  /// 1 to 12.
  public let month: Int

  public init(year: Int, month: Int) {
    precondition((1...12).contains(month), "month \(month) is not 1 to 12")
    self.year = year
    self.month = month
  }

  public static func < (a: CaptureMonth, b: CaptureMonth) -> Bool {
    (a.year, a.month) < (b.year, b.month)
  }

  /// `YYYY-MM`, which every `PhotoMetadata.takenAt` in this month starts with and sorts after.
  var prefix: String { String(format: "%04d-%02d", year, month) }

  var next: CaptureMonth {
    month == 12
      ? CaptureMonth(year: year + 1, month: 1) : CaptureMonth(year: year, month: month + 1)
  }
}

/// A photo in the library: its path relative to the library folder, and its details once the
/// scan has read them.
public struct PhotoRecord: Equatable, Sendable {
  public let id: Int64
  public let path: String
  /// Nil until the scan reads the file, and for a file with no image in it.
  public let metadata: PhotoMetadata?
}

/// The photo library database: one row per photo file, with its EXIF details once read, and a
/// cache of place names. Everything in it can be rebuilt from the files, so it lives in Caches.
///
/// One connection. Like `SQLiteDatabase` it isn't `Sendable`: open one per thread or actor. In
/// WAL mode the scan's commits reach other connections as they happen.
public final class PhotoLibrary {
  public static var defaultURL: URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
    return caches[0].appendingPathComponent("photo-screensaver/library.sqlite")
  }

  /// The SQL of the tables is their identity (ADR 0005): the database stores the text it was
  /// built from, and any difference on open drops everything and builds it anew, which the next
  /// scan refills. Pre-release, so no versions and no migrations. SQLite 3.36 at most, the
  /// version macOS 12 ships: no STRICT tables or unixepoch().
  static let schema = """
    -- The library folder the photos belong to, as one row. Another folder discards them.
    CREATE TABLE library (root TEXT NOT NULL);
    CREATE TABLE photos (
      -- A changed file is replaced by a new row. AUTOINCREMENT, so an ID is never used again:
      -- the feed and the slide history hold IDs, and a reused one would be another photo.
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      -- Relative to the library folder.
      path TEXT NOT NULL UNIQUE,
      size INTEGER NOT NULL,
      -- Seconds since 1970, compared exactly with the walk's value to skip unchanged files.
      mtime REAL NOT NULL,
      -- 0: details not read yet; 1: read; 2: no image in the file.
      read_state INTEGER NOT NULL DEFAULT 0,
      -- EXIF DateTimeOriginal as 'YYYY-MM-DD HH:MM:SS', the camera's local time, and
      -- OffsetTimeOriginal such as '+02:00'. Text sorts by year and month as it is.
      taken_at TEXT,
      taken_offset TEXT,
      -- As displayed, with EXIF rotation applied.
      width INTEGER,
      height INTEGER,
      make TEXT,
      model TEXT,
      lens TEXT,
      f_number REAL,
      -- Seconds.
      exposure REAL,
      iso INTEGER,
      -- Millimeters, actual and 35mm-equivalent.
      focal_length REAL,
      focal_35 INTEGER,
      -- Degrees, negative south and west; meters.
      latitude REAL,
      longitude REAL,
      altitude REAL
    );
    CREATE INDEX photos_taken_at ON photos (taken_at);
    -- The scan reads details in ID order, which is walk order, so a folder's files are read
    -- together.
    CREATE INDEX photos_unread ON photos (id) WHERE read_state = 0;
    -- Place names looked up for photo locations, keyed by rounded coordinates so photos taken
    -- near each other share one lookup. Kept when the library folder changes.
    CREATE TABLE places (
      lat_key INTEGER NOT NULL,
      lon_key INTEGER NOT NULL,
      name TEXT NOT NULL,
      PRIMARY KEY (lat_key, lon_key)
    ) WITHOUT ROWID;
    """
  static let identityTable = "schema_identity"

  enum ReadState: Int {
    case unread = 0
    case read = 1
    case notAnImage = 2
  }

  let database: SQLiteDatabase
  private let log = Logger(subsystem: "com.dylanfisher.photo-screensaver", category: "library")

  /// Opens or creates the database at `url`, rebuilding it if its tables don't match this build.
  public init(at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    database = try SQLiteDatabase(at: url)
    try prepareSchema()
  }

  /// Deletes the database at `url` with its log, for a file SQLite can't read.
  public static func discard(at url: URL) throws {
    for path in [url.path] + SQLiteDatabase.companionSuffixes.map({ url.path + $0 })
    where FileManager.default.fileExists(atPath: path) {
      try FileManager.default.removeItem(atPath: path)
    }
  }

  private func prepareSchema() throws {
    try database.execute("CREATE TABLE IF NOT EXISTS \(Self.identityTable) (sql TEXT NOT NULL)")
    // Checked outside a transaction first, so an open that has nothing to rebuild doesn't wait
    // for a scan's write lock.
    guard try storedSchema() != Self.schema else { return }
    try database.transaction {
      // Another connection may have rebuilt it in between.
      guard try storedSchema() != Self.schema else { return }
      let tables = try database.prepare(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
      ).map { try $0.text(0) }
      if tables.contains(where: { $0 != Self.identityTable }) {
        log.notice("library tables don't match this build; rebuilding them")
      }
      for table in tables where table != Self.identityTable {
        try database.execute("DROP TABLE \"\(table.replacingOccurrences(of: "\"", with: "\"\""))\"")
      }
      try database.execute(Self.schema)
      try database.execute("DELETE FROM \(Self.identityTable)")
      try database.prepare("INSERT INTO \(Self.identityTable) (sql) VALUES (?)").run(Self.schema)
    }
  }

  private func storedSchema() throws -> String? {
    try database.prepare("SELECT sql FROM \(Self.identityTable)").map { try $0.text(0) }.first
  }

  // MARK: Library folder

  /// The library folder's path, or nil before `use(root:)`.
  public func root() throws -> String? {
    try database.prepare("SELECT root FROM library").map { try $0.text(0) }.first
  }

  /// Makes `root` the folder this database describes, discarding the photos of any other.
  public func use(root: URL) throws {
    let path = Self.path(of: root)
    try database.transaction {
      guard try self.root() != path else { return }
      try database.execute("DELETE FROM photos; DELETE FROM library")
      try database.prepare("INSERT INTO library (root) VALUES (?)").run(path)
    }
  }

  /// How a folder is spelled in the database and in paths built on it.
  static func path(of root: URL) -> String { root.standardizedFileURL.path }

  /// Throws unless the database still describes `root`. Every scan write checks this in its
  /// transaction, so a scan of a folder the settings have moved away from can't mix its photos
  /// into the new folder's.
  private func require(root: String) throws {
    guard try self.root() == root else {
      throw LibraryError(description: "the library folder changed during the scan of \(root)")
    }
  }

  // MARK: Queries

  /// Photos that can be shown: every file the scan found, less those with no image in them.
  public func count() throws -> Int {
    try integer("SELECT count(*) FROM photos WHERE read_state <> 2")
  }

  /// IDs of the photos that can be shown, all of them or those taken in `months`. Photos whose
  /// capture date isn't known, including those not read yet, are only in the first.
  public func photoIDs(takenIn months: ClosedRange<CaptureMonth>? = nil) throws -> [Int64] {
    guard let months else {
      return try database.prepare("SELECT id FROM photos WHERE read_state <> 2").map {
        try $0.int64(0)
      }
    }
    return try database.prepare("SELECT id FROM photos WHERE taken_at >= ? AND taken_at < ?").map(
      months.lowerBound.prefix, months.upperBound.next.prefix
    ) { try $0.int64(0) }
  }

  /// How many photos were taken in each year, for years with any.
  public func yearCounts() throws -> [Int: Int] {
    let rows = try database.prepare(
      """
      SELECT CAST(substr(taken_at, 1, 4) AS INTEGER), count(*) FROM photos
      WHERE taken_at IS NOT NULL GROUP BY 1
      """
    ).map { (try $0.int(0), try $0.int(1)) }
    return Dictionary(uniqueKeysWithValues: rows)
  }

  /// Nil when no photo has `id`, e.g. because a scan removed or replaced it.
  public func photo(_ id: Int64) throws -> PhotoRecord? {
    try database.prepare(
      """
      SELECT path, read_state, width, height, taken_at, taken_offset, make, model, lens,
        f_number, exposure, iso, focal_length, focal_35, latitude, longitude, altitude
      FROM photos WHERE id = ?
      """
    ).map(id) { row in
      var metadata: PhotoMetadata?
      if try row.int(1) == ReadState.read.rawValue {
        metadata = PhotoMetadata(
          width: try row.int(2), height: try row.int(3), takenAt: row.optionalText(4),
          takenOffset: row.optionalText(5), make: row.optionalText(6),
          model: row.optionalText(7), lens: row.optionalText(8), fNumber: row.optionalDouble(9),
          exposure: row.optionalDouble(10), iso: row.optionalInt(11),
          focalLength: row.optionalDouble(12), focalLength35mm: row.optionalInt(13),
          latitude: row.optionalDouble(14), longitude: row.optionalDouble(15),
          altitude: row.optionalDouble(16))
      }
      return PhotoRecord(id: id, path: try row.text(0), metadata: metadata)
    }.first
  }

  // MARK: Scanning

  /// Every row's size and mtime by path, for the walk to tell new and changed files.
  func knownFiles() throws -> [String: WalkedFile] {
    var known: [String: WalkedFile] = [:]
    let files = try database.prepare("SELECT path, size, mtime FROM photos").map { row in
      WalkedFile(path: try row.text(0), size: try row.int(1), mtime: try row.double(2))
    }
    for file in files {
      known[file.path] = file
    }
    return known
  }

  /// Adds new files and replaces changed ones with new, unread rows.
  func insert(_ files: [WalkedFile], root: String) throws {
    try database.transaction {
      try require(root: root)
      let insert = try database.prepare(
        "INSERT OR REPLACE INTO photos (path, size, mtime) VALUES (?, ?, ?)")
      for file in files { try insert.run(file.path, file.size, file.mtime) }
    }
  }

  func remove(_ paths: [String], root: String) throws {
    try database.transaction {
      try require(root: root)
      let delete = try database.prepare("DELETE FROM photos WHERE path = ?")
      for path in paths { try delete.run(path) }
    }
  }

  /// Up to `limit` rows whose details aren't read, in ID order, after `id`.
  func unread(after id: Int64, limit: Int) throws -> [(id: Int64, path: String)] {
    try database.prepare(
      "SELECT id, path FROM photos WHERE read_state = 0 AND id > ? ORDER BY id LIMIT ?"
    ).map(id, limit) { (id: try $0.int64(0), path: try $0.text(1)) }
  }

  /// Stores what reading each file found: its details, or nil for no image in it.
  func store(_ results: [(id: Int64, metadata: PhotoMetadata?)], root: String) throws {
    try database.transaction {
      try require(root: root)
      let update = try database.prepare(
        """
        UPDATE photos SET read_state = ?, width = ?, height = ?, taken_at = ?, taken_offset = ?,
          make = ?, model = ?, lens = ?, f_number = ?, exposure = ?, iso = ?, focal_length = ?,
          focal_35 = ?, latitude = ?, longitude = ?, altitude = ?
        WHERE id = ?
        """)
      for (id, metadata) in results {
        let state = metadata == nil ? ReadState.notAnImage : ReadState.read
        try update.run(
          state.rawValue, metadata?.width, metadata?.height, metadata?.takenAt,
          metadata?.takenOffset, metadata?.make, metadata?.model, metadata?.lens,
          metadata?.fNumber, metadata?.exposure, metadata?.iso, metadata?.focalLength,
          metadata?.focalLength35mm, metadata?.latitude, metadata?.longitude, metadata?.altitude,
          id)
      }
    }
  }

  /// Every row, and those whose details aren't read yet.
  func counts() throws -> (photos: Int, unread: Int) {
    (
      try integer("SELECT count(*) FROM photos"),
      try integer("SELECT count(*) FROM photos WHERE read_state = 0")
    )
  }

  /// The one value a query like `SELECT count(*)` returns.
  private func integer(_ sql: String) throws -> Int {
    let values = try database.prepare(sql).map(row: { try $0.int(0) })
    guard values.count == 1 else {
      throw LibraryError(description: "\(values.count) rows, not one, from: \(sql)")
    }
    return values[0]
  }
}
