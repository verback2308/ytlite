//
//  SZDatabase.swift
//

import Foundation
import SQLite3

let SQLITE_RESULT_FAILED = 0

private let SQLITE_DATE = SQLITE_NULL + 1
private let SQLITE_STATIC = unsafeBitCast(0, to:sqlite3_destructor_type.self)
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to:sqlite3_destructor_type.self)

class SZDatabase: NSObject {

    private var queue = DispatchQueue(label: "com.SZDatabase.queue")
    private var db: OpaquePointer? = nil
    private lazy var fmt: DateFormatter = createDateFormatter()

    override init() {
        super.init()
    }

    deinit {
        closeDB()
    }

    func open(dbPath: String) -> Bool {
        if db != nil {
            closeDB()
        }

        if let path = dbPath.cString(using:String.Encoding.utf8) {
            let result = sqlite3_open(path, &db)
            if result != SQLITE_OK {
                SZLogError("failed to open DB")
                sqlite3_close(db)

                return false
            }
        }

        return true
    }

    func closeDB() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    @discardableResult
    func execute(sql: String, params: [Any]? = nil) -> Int {
        guard let _ = db else {
            SZLogError("Database has not been opened!")
            return SQLITE_RESULT_FAILED
        }

        var result = SQLITE_RESULT_FAILED
        if let stmt = prepare(sql:sql, params:params) {
            result = execute(stmt:stmt, sql:sql)
        }

        return result
    }

    func query(sql: String, params: [Any]? = nil) -> [[String: Any]] {
        guard let _ = db else {
            SZLogError("Database has not been opened!")
            return []
        }

        var rows = [[String:Any]]()
        if let stmt = prepare(sql:sql, params:params) {
            rows = query(stmt:stmt, sql:sql)
        }

        return rows
    }

    func inQueue(_ block: (SZDatabase) -> Void) {
        queue.sync {
            block(self)
        }
    }

    func inTransaction(_ block: (SZDatabase, _ rollback: inout Bool) -> Void) {
        queue.sync {
            var shouldRollback: Bool = false

            beginTransaction()
            block(self, &shouldRollback)

            if shouldRollback {
                rollbackTransaction()
            } else {
                commitTransaction()
            }
        }
    }

    func lastErrorMessage() -> String {
        guard let _ = db else {
            SZLogError("Database has not been opened!")
            return "Unkwon"
        }

        if let msg = String(utf8String: sqlite3_errmsg(db)) {
            return msg
        }

        return "Unkwon"
    }

    func columnExist(columnName: String, tableName: String) -> Bool {
        let schema = getTableSchema(tableName: tableName)
        for value in schema {
            if let column = value["name"] as? String,
               column == columnName
            {
                return true
            }
        }

        return false
    }

}

// MARK:- Private

private extension SZDatabase {

    /// Private method to prepare an SQL statement before executing it.
    ///
    /// - Parameters:
    ///   - sql: The SQL query or command to be prepared.
    ///   - params: An array of optional parameters in case the SQL statement includes bound parameters - indicated by `?`
    /// - Returns: A pointer to a finalized SQLite statement that can be used to execute the query later
    private func prepare(sql: String, params: [Any]? = nil) -> OpaquePointer? {
        var stmt: OpaquePointer? = nil
        let cSql = sql.cString(using: String.Encoding.utf8)
        // Prepare
        let result = sqlite3_prepare_v2(self.db, cSql!, -1, &stmt, nil)
        if result != SQLITE_OK {
            sqlite3_finalize(stmt)
            if let error = String(validatingUTF8:sqlite3_errmsg(self.db)) {
                let msg = "failed to prepare SQL: \(sql), Error: \(error)"
                SZLogError(msg)
            }

            return nil
        }
        // Bind parameters, if any
        if let params = params {
            // Validate parameters
            let cntParams = sqlite3_bind_parameter_count(stmt)
            let cnt = params.count
            if cntParams != CInt(cnt) {
                let msg = "failed to bind parameters, counts did not match. SQL: \(sql), Parameters: \(params)"
                SZLogError(msg)

                return nil
            }
            var flag: CInt = 0
            // Text & BLOB values passed to a C-API do not work correctly if they are not marked as transient.
            for ndx in 1...cnt {
                // Check for data types
                if let txt = params[ndx-1] as? String {
                    flag = sqlite3_bind_text(stmt, CInt(ndx), txt, -1, SQLITE_TRANSIENT)
                } else if let data = params[ndx-1] as? NSData {
                    flag = sqlite3_bind_blob(stmt, CInt(ndx), data.bytes, CInt(data.length), SQLITE_TRANSIENT)
                } else if let date = params[ndx-1] as? Date {
                    let txt = fmt.string(from:date)
                    flag = sqlite3_bind_text(stmt, CInt(ndx), txt, -1, SQLITE_TRANSIENT)
                } else if let val = params[ndx-1] as? Bool {
                    let num = val ? 1 : 0
                    flag = sqlite3_bind_int(stmt, CInt(ndx), CInt(num))
                } else if let val = params[ndx-1] as? Double {
                    flag = sqlite3_bind_double(stmt, CInt(ndx), CDouble(val))
                } else if let val = params[ndx-1] as? Int {
                    flag = sqlite3_bind_int(stmt, CInt(ndx), CInt(val))
                } else if let val = params[ndx-1] as? Int64 {
                    flag = sqlite3_bind_int64(stmt, Int32(ndx), CLongLong(val))
                } else {
                    flag = sqlite3_bind_null(stmt, CInt(ndx))
                }
                // Check for errors
                if flag != SQLITE_OK {
                    sqlite3_finalize(stmt)
                    if let error = String(validatingUTF8:sqlite3_errmsg(self.db)) {
                        let msg = "SQLiteDB - failed to bind for SQL: \(sql), Parameters: \(params), Index: \(ndx) Error: \(error)"
                        SZLogError(msg)
                    }

                    return nil
                }
            }
        }
        return stmt
    }

    /// Private method which handles the actual execution of an SQL statement which had been prepared previously.
    ///
    /// - Parameters:
    ///   - stmt: The previously prepared SQLite statement
    ///   - sql: The SQL command to be excecuted
    /// - Returns: The ID for the last inserted row (if it was an INSERT command and the ID is an integer column) or a result code indicating the status of the command execution. A non-zero result indicates success and a 0 indicates failure.
    private func execute(stmt: OpaquePointer, sql: String) -> Int {
        // Step
        let res = sqlite3_step(stmt)
        if res != SQLITE_OK && res != SQLITE_DONE {
            sqlite3_finalize(stmt)
            if let error = String(validatingUTF8:sqlite3_errmsg(self.db)) {
                let msg = "failed to execute SQL: \(sql), Error: \(error)"
                SZLogError(msg)
            }

            return SQLITE_RESULT_FAILED
        }
        // Is this an insert
        let upp = sql.uppercased()
        var result = 0
        if upp.hasPrefix("INSERT ") {
            // Known limitations: http://www.sqlite.org/c3ref/last_insert_rowid.html
            let rid = sqlite3_last_insert_rowid(db)
            result = Int(rid)
        } else if upp.hasPrefix("DELETE") || upp.hasPrefix("UPDATE") {
            var cnt = sqlite3_changes(db)
            if cnt == 0 {
                cnt += 1
            }
            result = Int(cnt)
        } else {
            result = 1
        }
        // Finalize
        sqlite3_finalize(stmt)

        return result
    }

    /// Private method which handles the actual execution of an SQL query which had been prepared previously.
    ///
    /// - Parameters:
    ///   - stmt: The previously prepared SQLite statement
    ///   - sql: The SQL query to be run
    /// - Returns: An empty array if the query resulted in no rows. Otherwise, an array of dictionaries where each dictioanry key is a column name and the value is the column value.
    private func query(stmt: OpaquePointer, sql: String) -> [[String:Any]] {
        var rows = [[String:Any]]()
        var fetchColumnInfo = true
        var columnCount: CInt = 0
        var columnNames = [String]()
        var columnTypes = [CInt]()
        var result = sqlite3_step(stmt)
        while result == SQLITE_ROW {
            // Should we get column info?
            if fetchColumnInfo {
                columnCount = sqlite3_column_count(stmt)
                for index in 0..<columnCount {
                    // Get column name
                    let name = sqlite3_column_name(stmt, index)
                    columnNames.append(String(validatingUTF8:name!)!)
                    // Get column type
                    columnTypes.append(getColumnType(index:index, stmt:stmt))
                }
                fetchColumnInfo = false
            }
            // Get row data for each column
            var row = [String:Any]()
            for index in 0..<columnCount {
                let key = columnNames[Int(index)]
                let type = columnTypes[Int(index)]
                if let val = getColumnValue(index:index, type:type, stmt:stmt) {
                    //                        NSLog("Column type:\(type) with value:\(val)")
                    row[key] = val
                }
            }
            rows.append(row)
            // Next row
            result = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        return rows
    }

    /// Private method that returns the declared SQLite data type for a specific column in a pre-prepared SQLite statement.
    ///
    /// - Parameters:
    ///   - index: The 0-based index of the column
    ///   - stmt: The previously prepared SQLite statement
    /// - Returns: A CInt value indicating the SQLite data type
    private func getColumnType(index: CInt, stmt: OpaquePointer) -> CInt {
        var type:CInt = 0
        // Column types - http://www.sqlite.org/datatype3.html (section 2.2 table column 1)
        let blobTypes = ["BINARY", "BLOB", "VARBINARY"]
        let charTypes = ["CHAR", "CHARACTER", "CLOB", "NATIONAL VARYING CHARACTER", "NATIVE CHARACTER", "NCHAR", "NVARCHAR", "TEXT", "VARCHAR", "VARIANT", "VARYING CHARACTER"]
        let dateTypes = ["DATE", "DATETIME", "TIME", "TIMESTAMP"]
        let intTypes  = ["BIGINT", "BIT", "BOOL", "BOOLEAN", "INT", "INT2", "INT8", "INTEGER", "MEDIUMINT", "SMALLINT", "TINYINT"]
        let nullTypes = ["NULL"]
        let realTypes = ["DECIMAL", "DOUBLE", "DOUBLE PRECISION", "FLOAT", "NUMERIC", "REAL"]
        // Determine type of column - http://www.sqlite.org/c3ref/c_blob.html
        let buf = sqlite3_column_decltype(stmt, index)
        if buf != nil {
            var tmp = String(validatingUTF8:buf!)!.uppercased()
            // Remove bracketed section
            if let pos = tmp.range(of:"(") {
                tmp = String(tmp[..<pos.lowerBound])
            }

            if intTypes.contains(tmp) {
                return SQLITE_INTEGER
            }
            if realTypes.contains(tmp) {
                return SQLITE_FLOAT
            }
            if charTypes.contains(tmp) {
                return SQLITE_TEXT
            }
            if blobTypes.contains(tmp) {
                return SQLITE_BLOB
            }
            if nullTypes.contains(tmp) {
                return SQLITE_NULL
            }
            if dateTypes.contains(tmp) {
                return SQLITE_DATE
            }

            return SQLITE_TEXT
        } else {
            // For expressions and sub-queries
            type = sqlite3_column_type(stmt, index)
        }

        return type
    }

    // Get column value
    /// Private method to return the column value for a specified SQLite column.
    ///
    /// - Parameters:
    ///   - index: The 0-based index of the column
    ///   - type: The declared SQLite data type for the column
    ///   - stmt: The previously prepared SQLite statement
    /// - Returns: A value for the column if the data is of a recognized SQLite data type, or nil if the value was NULL
    private func getColumnValue(index: CInt, type: CInt, stmt: OpaquePointer) -> Any? {
        if type == SQLITE_INTEGER {
            let val = sqlite3_column_int64(stmt, index)
            return Int(val)
        }

        if type == SQLITE_FLOAT {
            let val = sqlite3_column_double(stmt, index)
            return Double(val)
        }

        if type == SQLITE_BLOB {
            let data = sqlite3_column_blob(stmt, index)
            let size = sqlite3_column_bytes(stmt, index)
            let val = NSData(bytes:data, length:Int(size))
            return val
        }

        if type == SQLITE_NULL {
            return nil
        }

        if type == SQLITE_DATE {
            // Is this a text date
            if let ptr = UnsafeRawPointer.init(sqlite3_column_text(stmt, index)) {
                let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
                if let txt = String(validatingUTF8:uptr) {
                    // Get date from string
                    if let dt = fmt.date(from: txt) {
                        return dt
                    } else {
                        NSLog("String value: \(txt) but could not be converted to date!")
                    }
                }
            }

            // If not a text date, then it's a time interval
            let val = sqlite3_column_double(stmt, index)
            let dt = Date(timeIntervalSince1970: val)

            return dt
        }

        // If nothing works, return a string representation
        if let ptr = UnsafeRawPointer.init(sqlite3_column_text(stmt, index)) {
            let uptr = ptr.bindMemory(to:CChar.self, capacity:0)
            let txt = String(validatingUTF8:uptr)
            return txt
        }

        return nil
    }

    func beginTransaction() {
        guard let _ = db else {
            SZLogError("Database has not been opened!")
            return
        }

        let sql = "BEGIN EXCLUSIVE TRANSACTION"
        if let stmt = prepare(sql:sql) {
            _ = execute(stmt:stmt, sql:sql)
        }
    }

    func rollbackTransaction() {
        guard let _ = db else {
            SZLogError("Database has not been opened!")
            return
        }

        let sql = "ROLLBACK TRANSACTION"
        if let stmt = prepare(sql:sql) {
            _ = execute(stmt:stmt, sql:sql)
        }
    }

    func commitTransaction() {
        guard let _ = db else {
            SZLogError("Database has not been opened!")
            return
        }

        let sql = "COMMIT TRANSACTION"
        if let stmt = prepare(sql:sql) {
            _ = execute(stmt:stmt, sql:sql)
        }
    }

    func getTableSchema(tableName: String) -> [[String: Any]] {
        let sql = "PRAGMA table_info(\(tableName))"
        return query(sql: sql)
    }

}

// MARK: - Getter

extension SZDatabase {

    private func createDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT:0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return formatter
    }

}


