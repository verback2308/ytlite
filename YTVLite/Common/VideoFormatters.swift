import Foundation

enum VideoFormatters {

    private static let iso8601Formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Formats a relative date from an ISO 8601 string.
    /// If the string is not ISO 8601 (e.g. already "6 hours ago"), returns it as-is.
    static func formatRelativeDate(_ iso: String) -> String {
        guard let date = iso8601Formatter.date(from: iso) else { return iso }
        let s = -date.timeIntervalSinceNow
        if s < 3600      { return "\(max(1, Int(s / 60)))m ago" }
        if s < 86400     { return "\(Int(s / 3600))h ago" }
        if s < 86400*30  { return "\(Int(s / 86400))d ago" }
        if s < 86400*365 { return "\(Int(s / 86400 / 30))mo ago" }
        return "\(Int(s / 86400 / 365))y ago"
    }

    /// Approximates a Date from a relative time string like "2 hours ago" / "3 дня назад".
    /// Returns nil if not parseable.
    static func approximateDate(fromRelative text: String) -> Date? {
        let t = text.lowercased()
        // Extract leading number (default 1 if not found)
        let n = t.components(separatedBy: .whitespaces)
            .compactMap(Int.init).first ?? 1
        let now = Date()
        if t.contains("sec") || t.contains("сек")   { return now - Double(n) }
        if t.contains("min") || t.contains("мин")   { return now - Double(n) * 60 }
        if t.contains("hour") || t.contains("час")  { return now - Double(n) * 3600 }
        if t.contains("day") || t.contains("дн")
            || t.contains("день") || t.contains("дня") { return now - Double(n) * 86400 }
        if t.contains("week") || t.contains("нед")  { return now - Double(n) * 604_800 }
        if t.contains("month") || t.contains("мес") { return now - Double(n) * 2_592_000 }
        if t.contains("year") || t.contains("лет")
            || t.contains("год")                     { return now - Double(n) * 31_536_000 }
        return nil
    }

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
