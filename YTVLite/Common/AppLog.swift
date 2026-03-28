import Foundation

/// Lightweight timestamped logger. All output goes to console.
/// Format: [HH:mm:ss.SSS] [tag] message
enum AppLog {
    private static let fmt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ tag: String, _ message: String) {
        let ts = fmt.string(from: Date())
        // swiftlint:disable:next no_debug_print
        print("[\(ts)] [\(tag)] \(message)")
    }

    // Convenience namespaces
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
