import Foundation

enum VideoFormatters {

    /// Formats a relative date from an ISO 8601 string.
    /// If the string is not ISO 8601 (e.g. already "6 hours ago"), returns it as-is.
    static func formatRelativeDate(_ iso: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let date = fmt.date(from: iso) else { return iso }
        let s = -date.timeIntervalSinceNow
        if s < 3600      { return "\(max(1, Int(s / 60)))m ago" }
        if s < 86400     { return "\(Int(s / 3600))h ago" }
        if s < 86400*30  { return "\(Int(s / 86400))d ago" }
        if s < 86400*365 { return "\(Int(s / 86400 / 30))mo ago" }
        return "\(Int(s / 86400 / 365))y ago"
    }

    /// Converts ISO 8601 duration (PT1H2M3S) to display string (1:02:03 or 4:32).
    static func parseDuration(_ iso: String) -> String {
        var h = 0, m = 0, s = 0
        var current = ""
        for ch in iso.dropFirst(2) { // drop "PT"
            if ch.isNumber { current.append(ch) }
            else if ch == "H" { h = Int(current) ?? 0; current = "" }
            else if ch == "M" { m = Int(current) ?? 0; current = "" }
            else if ch == "S" { s = Int(current) ?? 0; current = "" }
        }
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Formats a raw view count string ("1400000000") to a readable form ("1.4B views").
    /// If the string is already formatted (not a plain number), returns it as-is.
    static func formatViewCount(_ raw: String) -> String {
        guard let n = Int(raw) else { return raw }
        switch n {
        case 1_000_000_000...: return String(format: "%.1fB views", Double(n) / 1e9)
        case 1_000_000...:     return String(format: "%.1fM views", Double(n) / 1e6)
        case 1_000...:         return String(format: "%.0fK views", Double(n) / 1e3)
        default:               return "\(n) views"
        }
    }
}
