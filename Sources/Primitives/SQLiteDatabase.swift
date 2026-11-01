import Foundation
import SQLite3

/// A failed SQLite call: the result code, SQLite's message, and the SQL it was running.
public struct SQLiteError: Error, Equatable, CustomStringConvertible {
  /// The extended result code, such as `SQLITE_CONSTRAINT_UNIQUE`.
  public var code: Int32
  public var message: String
  /// Nil for calls that run no SQL, such as opening the file.
  public var sql: String?

  public var description: String {
    "SQLite error \(code): \(message)" + (sql.map { " in: \($0)" } ?? "")
  }

  /// SQLITE_NOTADB or SQLITE_CORRUPT: the file isn't a database SQLite can read, as opposed to
  /// one it can't reach right now, such as a locked or full one.
  public var isUnreadableFile: Bool { [SQLITE_NOTADB, SQLITE_CORRUPT].contains(code & 0xFF) }
}

extension SQLiteError {
  /// The connection's last error, which describes the call that just failed.
  init(_ connection: OpaquePointer?, sql: String?) {
    code = sqlite3_extended_errcode(connection)
    message = String(cString: sqlite3_errmsg(connection))
    self.sql = sql
  }
}

/// One connection to a SQLite database file, in WAL mode so readers on other connections run
/// alongside a writer.
///
/// Opened in SQLite's multi-thread mode, so a connection must never be used by two threads at
/// once. It isn't `Sendable`, which keeps it, and the statements prepared on it, inside one
/// thread or actor, or behind the caller's own lock. Open one per thread or actor that needs one.
public final class SQLiteDatabase {
  /// How long a call waits for another connection's lock before failing with `SQLITE_BUSY`.
  static let busyTimeoutMs: Int32 = 5000

  let connection: OpaquePointer

  /// Opens or creates the file at `url`.
  public init(at url: URL) throws {
    var connection: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(url.path, &connection, flags, nil) == SQLITE_OK, let connection else {
      let error = SQLiteError(connection, sql: nil)
      sqlite3_close_v2(connection)
      throw SQLiteError(code: error.code, message: "\(url.path): \(error.message)", sql: nil)
    }
    self.connection = connection
    sqlite3_extended_result_codes(connection, 1)
    sqlite3_busy_timeout(connection, Self.busyTimeoutMs)
    // Switching a new file to WAL takes a lock SQLite doesn't wait for with the busy timeout,
    // so connections opening the same new file at once retry it within that time.
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(Self.busyTimeoutMs) * 1_000_000
    while true {
      do {
        try execute("PRAGMA journal_mode = WAL")
        break
      } catch let error as SQLiteError
        where error.code & 0xFF == SQLITE_BUSY && DispatchTime.now().uptimeNanoseconds < deadline
      {
        usleep(1000)
      }
    }
    // NORMAL is durable in WAL mode except across a power cut, which loses at most the last
    // few transactions.
    try execute("PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON")
  }

  deinit {
    // Closes once the last statement is finalized, since statements may outlive this.
    sqlite3_close_v2(connection)
  }

  /// Runs one or more statements that take no parameters, discarding any rows.
  public func execute(_ sql: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw SQLiteError(connection, sql: sql)
    }
  }

  public func prepare(_ sql: String) throws -> SQLiteStatement {
    try SQLiteStatement(self, sql)
  }

  /// Runs `body` in a transaction: committed when it returns, rolled back when it or the commit
  /// throws. `BEGIN IMMEDIATE` takes the write lock up front, so two writers wait on the busy
  /// timeout instead of failing at their first write.
  public func transaction<T>(_ body: () throws -> T) throws -> T {
    try execute("BEGIN IMMEDIATE")
    let result = Result(catching: body).flatMap { value in
      Result { try execute("COMMIT") }.map { value }
    }
    // SQLite rolls some failures back itself, such as SQLITE_FULL, and a second rollback would
    // fail. A failed COMMIT, such as SQLITE_BUSY or a deferred constraint, leaves the
    // transaction open, and every later BEGIN would fail.
    if case .failure = result, isInTransaction {
      // The error to report is the one that caused the rollback.
      try? execute("ROLLBACK")
    }
    return try result.get()
  }

  /// What SQLite adds to a database's path for its write-ahead log and its shared-memory index.
  public static let companionSuffixes = ["-wal", "-shm"]

  /// Whether a transaction is open on this connection.
  public var isInTransaction: Bool { sqlite3_get_autocommit(connection) == 0 }
}

/// SQLite copies bound text before the call returns. The C macro isn't imported into Swift.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A value a statement parameter can take. Nil binds NULL.
public protocol SQLiteValue {
  func bind(to statement: OpaquePointer, at index: Int32) -> Int32
}

extension Int: SQLiteValue {
  public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
    sqlite3_bind_int64(statement, index, Int64(self))
  }
}

extension Int64: SQLiteValue {
  public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
    sqlite3_bind_int64(statement, index, self)
  }
}

extension Double: SQLiteValue {
  public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
    sqlite3_bind_double(statement, index, self)
  }
}

extension String: SQLiteValue {
  /// Bound by its byte count, so text holding a NUL is bound whole.
  public func bind(to statement: OpaquePointer, at index: Int32) -> Int32 {
    guard let count = Int32(exactly: utf8.count) else { return SQLITE_TOOBIG }
    return sqlite3_bind_text(statement, index, self, count, transient)
  }
}

/// A prepared statement. Prepare it once and run it many times; each run resets it and binds its
/// parameters afresh. Belongs to its database's thread or actor.
public final class SQLiteStatement {
  private let database: SQLiteDatabase
  private let statement: OpaquePointer
  let sql: String

  init(_ database: SQLiteDatabase, _ sql: String) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database.connection, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else { throw SQLiteError(database.connection, sql: sql) }
    self.database = database
    self.statement = statement
    self.sql = sql
  }

  deinit { sqlite3_finalize(statement) }

  /// Runs a statement that returns no rows.
  public func run(_ values: (any SQLiteValue)?...) throws {
    try run(binding: values)
  }

  /// `run` with the values as a list, for callers that build them up.
  public func run(binding values: [(any SQLiteValue)?]) throws {
    try start(values)
    defer { sqlite3_reset(statement) }
    while try step() {}
  }

  /// The rows of a query, each mapped by `transform`.
  public func map<T>(_ values: (any SQLiteValue)?..., row transform: (SQLiteRow) throws -> T)
    throws -> [T]
  {
    try start(values)
    defer { sqlite3_reset(statement) }
    let row = SQLiteRow(statement: statement, sql: sql)
    var results: [T] = []
    while try step() { results.append(try transform(row)) }
    return results
  }

  private func start(_ values: [(any SQLiteValue)?]) throws {
    sqlite3_reset(statement)
    sqlite3_clear_bindings(statement)
    let expected = Int(sqlite3_bind_parameter_count(statement))
    guard values.count == expected else {
      throw SQLiteError(
        code: SQLITE_RANGE, message: "\(values.count) values for \(expected) parameters", sql: sql)
    }
    for (offset, value) in values.enumerated() {
      let index = Int32(offset + 1)
      let result = value?.bind(to: statement, at: index) ?? sqlite3_bind_null(statement, index)
      if result == SQLITE_TOOBIG {
        throw SQLiteError(code: result, message: "value \(index) is too big to bind", sql: sql)
      }
      guard result == SQLITE_OK else { throw SQLiteError(database.connection, sql: sql) }
    }
  }

  /// True when a row is ready, false when the statement is done.
  private func step() throws -> Bool {
    switch sqlite3_step(statement) {
    case SQLITE_ROW: return true
    case SQLITE_DONE: return false
    default: throw SQLiteError(database.connection, sql: sql)
    }
  }
}

/// The current row of a running query. Only valid inside the `map` call that produced it.
/// Columns are numbered from 0, in the order the SELECT lists them.
public struct SQLiteRow {
  let statement: OpaquePointer
  let sql: String

  public func isNull(_ column: Int32) -> Bool {
    sqlite3_column_type(statement, column) == SQLITE_NULL
  }

  public func int(_ column: Int32) throws -> Int {
    try notNull(column)
    return Int(sqlite3_column_int64(statement, column))
  }

  public func optionalInt(_ column: Int32) -> Int? {
    isNull(column) ? nil : Int(sqlite3_column_int64(statement, column))
  }

  public func int64(_ column: Int32) throws -> Int64 {
    try notNull(column)
    return sqlite3_column_int64(statement, column)
  }

  public func double(_ column: Int32) throws -> Double {
    try notNull(column)
    return sqlite3_column_double(statement, column)
  }

  public func optionalDouble(_ column: Int32) -> Double? {
    isNull(column) ? nil : sqlite3_column_double(statement, column)
  }

  public func text(_ column: Int32) throws -> String {
    try notNull(column)
    // SQLite returns no text for a value that isn't NULL only when it runs out of memory.
    guard let text = optionalText(column) else {
      throw SQLiteError(code: SQLITE_NOMEM, message: "column \(column) has no text", sql: sql)
    }
    return text
  }

  /// Read by its byte count, so text holding a NUL comes back whole.
  public func optionalText(_ column: Int32) -> String? {
    // SQLite's docs ask for the text first, then its length.
    guard let text = sqlite3_column_text(statement, column) else { return nil }
    let count = Int(sqlite3_column_bytes(statement, column))
    return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
  }

  /// A NULL where the caller expects a value means the schema and the query disagree.
  private func notNull(_ column: Int32) throws {
    guard !isNull(column) else {
      throw SQLiteError(code: SQLITE_MISMATCH, message: "column \(column) is NULL", sql: sql)
    }
  }
}
