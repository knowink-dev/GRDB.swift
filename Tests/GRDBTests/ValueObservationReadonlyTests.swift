import XCTest
#if GRDBCUSTOMSQLITE
import GRDBCustomSQLite
#else
#if SWIFT_PACKAGE
import CSQLite
#else
import SQLite3
#endif
import GRDB
#endif

class ValueObservationReadonlyTests: GRDBTestCase {
    
    func testReadOnlyObservation() throws {
        try assertValueObservation(
            ValueObservation.tracking(DatabaseRegion.fullDatabase, fetch: {
                try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM t")!
            }),
            records: [0, 1],
            setup: { db in
                try db.execute(sql: "CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT)")
        },
            recordedUpdates: { db in
                try db.execute(sql: "INSERT INTO t DEFAULT VALUES")
        })
    }
    
    func testWriteObservationFailsByDefaultWithErrorHandling() throws {
        try assertValueObservation(
            ValueObservation.tracking(DatabaseRegion.fullDatabase, fetch: { db -> Int in
                try db.execute(sql: "INSERT INTO t DEFAULT VALUES")
                return 0
            }),
            fails: { (error: DatabaseError, _: DatabaseWriter) in
                XCTAssertEqual(error.resultCode, .SQLITE_READONLY)
                XCTAssertEqual(error.message, "attempt to write a readonly database")
                XCTAssertEqual(error.sql!, "INSERT INTO t DEFAULT VALUES")
                XCTAssertEqual(error.description, "SQLite error 8 with statement `INSERT INTO t DEFAULT VALUES`: attempt to write a readonly database")
        },
            setup: { db in
                try db.execute(sql: "CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT)")
        })
    }
    
    func testWriteObservation() throws {
        var observation = ValueObservation.tracking(DatabaseRegion.fullDatabase, fetch: { db -> Int in
            XCTAssert(db.isInsideTransaction, "expected a wrapping transaction")
            try db.execute(sql: "CREATE TEMPORARY TABLE temp AS SELECT * FROM t")
            let result = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM temp")!
            try db.execute(sql: "DROP TABLE temp")
            return result
        })
        observation.requiresWriteAccess = true
        
        try assertValueObservation(
            observation,
            records: [0, 1],
            setup: { db in
                try db.execute(sql: "CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT)")
        },
            recordedUpdates: { db in
                try db.execute(sql: "INSERT INTO t DEFAULT VALUES")
        })
    }
    
    func testWriteObservationIsWrappedInSavepointWithErrorHandling() throws {
        struct TestError: Error { }
        var observation = ValueObservation.tracking(DatabaseRegion.fullDatabase, fetch: { db in
            try db.execute(sql: "INSERT INTO t DEFAULT VALUES")
            throw TestError()
        })
        observation.requiresWriteAccess = true
        
        try assertValueObservation(
            observation,
            fails: { (_: TestError, writer: DatabaseWriter) in
                let count = try writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM t")! }
                XCTAssertEqual(count, 0)
        },
            setup: { db in
                try db.execute(sql: "CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT)")
        })
    }
}