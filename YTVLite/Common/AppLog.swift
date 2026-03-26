import Foundation

/// Lightweight timestamped logger. All output goes to console.
/// Format: [HH:mm:ss.SSS] [tag] message
enum AppLog {
    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ tag: String, _ message: String) {
        let ts = fmt.string(from: Date())
        print("[\(ts)] [\(tag)] \(message)")
    }

    // Convenience namespaces
    static func home(_ msg: String)   { log("Home", msg) }
    static func subs(_ msg: String)   { log("Subs", msg) }
    static func cache(_ msg: String)  { log("Cache", msg) }
    static func img(_ msg: String)    { log("Img", msg) }
    static func channel(_ msg: String){ log("Channel", msg) }
    static func auth(_ msg: String)   { log("Auth", msg) }
}
