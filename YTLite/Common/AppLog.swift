import Foundation

/// Lightweight timestamped logger.
/// Writes to both console and a rotating log file in Caches/Logs/.
enum AppLog {
    private static let fmt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static let logQueue = DispatchQueue(
        label: "com.ytvlite.logger",
        qos: .utility
    )
    private static let maxFileSize: UInt64 = 512_000 // 512 KB
    private static var fileHandle: FileHandle?
    private static var currentFileSize: UInt64 = 0

    private static let logDirectory: URL = {
        let caches = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        )[0]
        let dir = caches.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }()

    static var currentLogURL: URL {
        logDirectory.appendingPathComponent("ytlite.log")
    }

    private static var previousLogURL: URL {
        logDirectory.appendingPathComponent("ytlite.prev.log")
    }

    static func log(_ tag: String, _ message: String) {
        let ts = fmt.string(from: Date())
        let line = "[\(ts)] [\(tag)] \(message)"
        // swiftlint:disable:next no_debug_print
        print(line)
        logQueue.async { writeLine(line) }
    }

    /// Returns combined log data (previous + current) for sharing.
    static func exportLogData() -> Data? {
        logQueue.sync {
            fileHandle?.synchronizeFile()
        }
        var combined = Data()
        if let prev = try? Data(contentsOf: previousLogURL) {
            combined.append(prev)
        }
        if let current = try? Data(contentsOf: currentLogURL) {
            combined.append(current)
        }
        return combined.isEmpty ? nil : combined
    }

    // MARK: - Private

    private static func writeLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8)
        else { return }
        let handle = getOrCreateHandle()
        handle.write(data)
        currentFileSize += UInt64(data.count)
        if currentFileSize >= maxFileSize {
            rotateLog()
        }
    }

    private static func getOrCreateHandle() -> FileHandle {
        if let handle = fileHandle {
            return handle
        }
        let url = currentLogURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(
                atPath: url.path, contents: nil
            )
        }
        guard let handle = FileHandle(
            forWritingAtPath: url.path
        ) else {
            return FileHandle.nullDevice
        }
        handle.seekToEndOfFile()
        currentFileSize = handle.offsetInFile
        fileHandle = handle
        return handle
    }

    private static func rotateLog() {
        fileHandle?.closeFile()
        fileHandle = nil
        let fm = FileManager.default
        try? fm.removeItem(at: previousLogURL)
        try? fm.moveItem(at: currentLogURL, to: previousLogURL)
        fm.createFile(atPath: currentLogURL.path, contents: nil)
        currentFileSize = 0
    }

    // MARK: - Convenience Namespaces

    static func home(_ msg: String) { log("Home", msg) }
    static func subs(_ msg: String) { log("Subs", msg) }
    static func cache(_ msg: String) { log("Cache", msg) }
    static func img(_ msg: String) { log("Img", msg) }
    static func channel(_ msg: String) { log("Channel", msg) }
    static func auth(_ msg: String) { log("Auth", msg) }
    static func innertube(_ msg: String) { log("Innertube", msg) }
    static func player(_ msg: String) { log("Player", msg) }
    static func hls(_ msg: String) { log("HLS", msg) }
    static func onesie(_ msg: String) { log("Onesie", msg) }
    static func sponsorBlock(_ msg: String) { log("SponsorBlock", msg) }
    static func ryd(_ msg: String) { log("RYD", msg) }
    static func poToken(_ msg: String) { log("PoToken", msg) }
    static func subscribe(_ msg: String) { log("Subscribe", msg) }
}
