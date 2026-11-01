import Primitives
import XCTest

final class SQLiteDatabaseTests: XCTestCase {
  private var dir: URL!
  private var database: SQLiteDatabase!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    database = try SQLiteDatabase(at: dir.appendingPathComponent("test.sqlite"))
    try database.execute("CREATE TABLE t (i INTEGER, d REAL, s TEXT)")
  }

  override func tearDownWithError() throws {
    database = nil
    try FileManager.default.removeItem(at: dir)
  }

  func testRoundTripsValuesAndNull() throws {
    try database.prepare("INSERT INTO t VALUES (?, ?, ?)").run(7, 2.5, "a\0b")
    try database.prepare("INSERT INTO t VALUES (?, ?, ?)").run(nil, nil, nil)
    let rows = try database.prepare("SELECT i, d, s FROM t ORDER BY rowid").map { row in
      [
        row.optionalInt(0).map { "\($0)" }, row.optionalDouble(1).map { "\($0)" },
        row.optionalText(2),
      ]
    }
    XCTAssertEqual(rows, [["7", "2.5", "a\0b"], [nil, nil, nil]])
  }

  func testNullWhereAValueIsExpectedThrows() throws {
    try database.prepare("INSERT INTO t VALUES (NULL, NULL, NULL)").run()
    XCTAssertThrowsError(try database.prepare("SELECT i FROM t").map { try $0.int(0) })
  }

  func testTransactionRollsBackWhenItsBodyThrows() throws {
    struct Failure: Error {}
    XCTAssertThrowsError(
      try database.transaction {
        try database.prepare("INSERT INTO t (i) VALUES (1)").run()
        throw Failure()
      })
    XCTAssertFalse(database.isInTransaction)
    XCTAssertEqual(try database.prepare("SELECT count(*) FROM t").map { try $0.int(0) }, [0])
  }

  func testTransactionCommitsWhenItsBodyReturns() throws {
    try database.transaction { try database.prepare("INSERT INTO t (i) VALUES (1)").run() }
    XCTAssertEqual(try database.prepare("SELECT count(*) FROM t").map { try $0.int(0) }, [1])
  }

  func testErrorsCarrySQLitesMessageAndTheSQL() {
    XCTAssertThrowsError(try database.prepare("SELEC 1")) { error in
      let error = error as? SQLiteError
      XCTAssertEqual(error?.sql, "SELEC 1")
      XCTAssertTrue(error?.message.contains("syntax error") == true, "\(String(describing: error))")
    }
  }

  func testWrongParameterCountThrows() {
    XCTAssertThrowsError(try database.prepare("INSERT INTO t (i) VALUES (?)").run(1, 2))
  }

  func testOpensInWALMode() throws {
    let mode = try database.prepare("PRAGMA journal_mode").map { try $0.text(0) }
    XCTAssertEqual(mode, ["wal"])
  }

  func testAFileThatIsNotADatabaseIsUnreadable() throws {
    let url = dir.appendingPathComponent("garbage.sqlite")
    try Data(repeating: 0x41, count: 4096).write(to: url)
    XCTAssertThrowsError(try SQLiteDatabase(at: url)) { error in
      XCTAssertTrue((error as? SQLiteError)?.isUnreadableFile == true, "\(error)")
    }
  }
}
