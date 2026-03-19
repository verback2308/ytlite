//
//  SZAVPlayerDatabase.swift
//  SZAVPlayer
//
//  Created by CaiSanze on 2019/11/28.
//

import UIKit

public class SZAVPlayerDatabase: NSObject {

    public static let shared = SZAVPlayerDatabase()

    private let dbQueue = SZDatabase()
    private let dbFileName = SZAVPlayerFileSystem.documentsDirectory.appendingPathComponent("SZAVPlayer.sqlite").absoluteString

    override init() {
        super.init()

        guard dbQueue.open(dbPath: dbFileName) else { return }

        createContentInfoTable()
        createLocalFileInfoTable()
    }

    deinit {
        dbQueue.closeDB()
    }

    public func cleanData() {
        dbQueue.inTransaction { (db, rollback) in
            let needDeleteTableNames: [String] = [
                SZAVPlayerContentInfo.tableName,
                SZAVPlayerLocalFileInfo.tableName,
            ]
            needDeleteTableNames.forEach { (tableName) in
                let sql = "DELETE FROM \(tableName)"
                db.execute(sql: sql)
            }
        }
    }

    public func trimData(uniqueID: String? = nil) {
        DispatchQueue.global(qos: .background).async {
            if let uniqueID = uniqueID, !uniqueID.isEmpty {
                self.delete(uniqueID: uniqueID)
            } else {
                let infos = self.expiredContentInfos()
                for info in infos {
                    self.delete(uniqueID: info.uniqueID)
                }
            }
        }
    }

}

// MARK: - ContentInfo

extension SZAVPlayerDatabase {

    public func contentInfo(uniqueID: String) -> SZAVPlayerContentInfo? {
        var info: SZAVPlayerContentInfo?
        dbQueue.inQueue { (db) in
            let sql = "SELECT * FROM \(SZAVPlayerContentInfo.tableName) WHERE uniqueID = ?"
            let infos = db.query(sql: sql, params: [uniqueID])
            if let infoDict = infos.first,
                let tmpInfo = SZAVPlayerContentInfo.deserialize(data: infoDict)
            {
                info = tmpInfo
            }
        }

        return info
    }

    public func update(contentInfo: SZAVPlayerContentInfo) {
        dbQueue.inQueue { (db) in
            let sql = "INSERT OR REPLACE INTO \(SZAVPlayerContentInfo.tableName) " +
            "(uniqueID, mimeType, contentLength, updated, isByteRangeAccessSupported) " +
            "values(?, ?, ?, ?, ?)"
            let updated = Int64(Date().timeIntervalSince1970)
            let params: [Any] = [contentInfo.uniqueID, contentInfo.mimeType, contentInfo.contentLength, updated, contentInfo.isByteRangeAccessSupported]
            db.execute(sql: sql, params: params)
        }
    }

    public func deleteMIMEType(uniqueID: String) {
        dbQueue.inQueue { (db) in
            let sql = "DELETE FROM \(SZAVPlayerContentInfo.tableName) WHERE uniqueID = ?"
            let params = [
                uniqueID
            ]
            db.execute(sql: sql, params: params)
        }
    }

    private func expiredContentInfos() -> [SZAVPlayerContentInfo] {
        var expiredInfos: [SZAVPlayerContentInfo] = []
        dbQueue.inQueue { (db) in
            let sql = "SELECT * FROM \(SZAVPlayerContentInfo.tableName) ORDER BY updated ASC LIMIT 5"
            let infos = db.query(sql: sql)
            if let infoDict = infos.first,
                let tmpInfo = SZAVPlayerContentInfo.deserialize(data: infoDict)
            {
                expiredInfos.append(tmpInfo)
            }
        }

        return expiredInfos
    }

    private func createContentInfoTable() {
        let tableName = SZAVPlayerContentInfo.tableName
        let sqlQuerys = [
            "CREATE TABLE IF NOT EXISTS \(tableName) (" +
            "id INTEGER PRIMARY KEY ASC, " +
            "uniqueID TEXT, " +
            "mimeType TEXT, " +
            "contentLength INTEGER, " +
            "updated INTEGER" +
            ");\n",
            "CREATE UNIQUE INDEX IF NOT EXISTS \(tableName)_uniqueID " +
            "ON \(tableName)(" +
            "uniqueID" +
            ");\n",
        ]

        createTable(sqlQuerys: sqlQuerys)

        if !dbQueue.columnExist(columnName: "isByteRangeAccessSupported", tableName: SZAVPlayerContentInfo.tableName) {
            let sql = "ALTER TABLE \(SZAVPlayerContentInfo.tableName) ADD COLUMN isByteRangeAccessSupported INTEGER DEFAULT 1"
            dbQueue.execute(sql: sql)
        }
    }

}

// MARK: - LocalFileInfo

extension SZAVPlayerDatabase {

    public func localFileInfos(uniqueID: String) -> [SZAVPlayerLocalFileInfo] {
        var fileInfos: [SZAVPlayerLocalFileInfo] = []
        dbQueue.inQueue { (db) in
            let sql = "SELECT * FROM \(SZAVPlayerLocalFileInfo.tableName) WHERE uniqueID = ? AND loadedByteLength > 0 ORDER BY startOffset ASC"
            let params = [
                uniqueID
            ]
            let infos = db.query(sql: sql, params: params)
            infos.forEach { (info) in
                if let fileInfo = SZAVPlayerLocalFileInfo.deserialize(data: info) {
                    fileInfos.append(fileInfo)
                }
            }
        }

        return fileInfos
    }

    public func update(fileInfo: SZAVPlayerLocalFileInfo) {
        dbQueue.inQueue { (db) in
            let sql = "INSERT OR REPLACE INTO \(SZAVPlayerLocalFileInfo.tableName) " +
            "(uniqueID, startOffset, loadedByteLength, localFileName, updated) " +
            "values(?, ?, ?, ?, ?)"
            let updated = Int64(Date().timeIntervalSince1970)
            let params: [Any] = [
                fileInfo.uniqueID,
                fileInfo.startOffset,
                fileInfo.loadedByteLength,
                fileInfo.localFileName,
                updated
            ]
            db.execute(sql: sql, params: params)
        }
    }

    public func deleteLocalFileInfo(uniqueID: String) {
        dbQueue.inQueue { (db) in
            let sql = "DELETE FROM \(SZAVPlayerLocalFileInfo.tableName) WHERE uniqueID = ?"
            let params = [
                uniqueID
            ]
            db.execute(sql: sql, params: params)
        }
    }

    private func createLocalFileInfoTable() {
        let tableName = SZAVPlayerLocalFileInfo.tableName
        let sqlQuerys = [
            "CREATE TABLE IF NOT EXISTS \(tableName) (" +
            "id INTEGER PRIMARY KEY ASC, " +
            "uniqueID TEXT, " +
            "startOffset INTEGER, " +
            "loadedByteLength INTEGER, " +
            "localFileName TEXT, " +
            "updated INTEGER" +
            ");\n",
            "CREATE UNIQUE INDEX IF NOT EXISTS \(tableName)_uniqueID_startOffset " +
            "ON \(tableName)(" +
            "uniqueID, startOffset" +
            ");\n",
        ]

        createTable(sqlQuerys: sqlQuerys)
    }

}

// MARK: - Private

private extension SZAVPlayerDatabase {

    func createTable(sqlQuerys: [String]) {
        dbQueue.inTransaction { (db, rollback) in
            for sql in sqlQuerys {
                if db.execute(sql: sql) == SQLITE_RESULT_FAILED {
                    rollback = true
                    break
                }
            }
        }
    }

    func delete(uniqueID: String) {
        self.deleteMIMEType(uniqueID: uniqueID)

        let fileInfos = self.localFileInfos(uniqueID: uniqueID)
        for fileInfo in fileInfos {
            let fileURL = SZAVPlayerFileSystem.localFilePath(fileName: fileInfo.localFileName)
            SZAVPlayerFileSystem.delete(url: fileURL)
        }
        self.deleteLocalFileInfo(uniqueID: uniqueID)
    }
    
}
