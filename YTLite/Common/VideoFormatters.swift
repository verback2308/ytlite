import Foundation

enum VideoFormatters {
    private static let iso8601Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Formats a relative date from an ISO 8601 string.
    /// If the string is not ISO 8601 (e.g. already "6 hours ago"), returns it as-is.
    static func formatRelativeDate(_ iso: String) -> String {
        guard let date = iso8601Formatter.date(from: iso) else {
            return iso
        }
        let seconds = -date.timeIntervalSinceNow
        if seconds < 3_600 {
            return "\(max(1, Int(seconds / 60)))m ago"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3_600))h ago"
        }
        if seconds < 86_400 * 30 {
            return "\(Int(seconds / 86_400))d ago"
        }
        if seconds < 86_400 * 365 {
            return "\(Int(seconds / 86_400 / 30))mo ago"
        }
        return "\(Int(seconds / 86_400 / 365))y ago"
    }

    /// Approximates a Date from a relative time string like "2 hours ago" / "3 дня назад".
    /// Returns nil if not parseable.
    static func approximateDate(fromRelative text: String) -> Date? {
        let lowered = text.lowercased()
        let num = lowered.components(separatedBy: .whitespaces)
            .compactMap(Int.init).first ?? 1
        let now = Date()
        if lowered.contains("sec") || lowered.contains("сек") {
            return now - Double(num)
        }
        if lowered.contains("min") || lowered.contains("мин") {
            return now - Double(num) * 60
        }
        if lowered.contains("hour") || lowered.contains("час") {
            return now - Double(num) * 3_600
        }
        if lowered.contains("day") || lowered.contains("дн")
            || lowered.contains("день") || lowered.contains("дня") {
            return now - Double(num) * 86_400
        }
        if lowered.contains("week") || lowered.contains("нед") {
            return now - Double(num) * 604_800
        }
        if lowered.contains("month") || lowered.contains("мес") {
            return now - Double(num) * 2_592_000
        }
        if lowered.contains("year") || lowered.contains("лет")
            || lowered.contains("год") {
            return now - Double(num) * 31_536_000
        }
        return nil
    }

    static func parseDuration(_ iso: String) -> String {
        var hours = 0, minutes = 0, secs = 0
        var current = ""
        for ch in iso.dropFirst(2) {
            if ch.isNumber {
                current.append(ch)
            } else if ch == "H" {
                hours = Int(current) ?? 0; current = ""
            } else if ch == "M" {
                minutes = Int(current) ?? 0; current = ""
            } else if ch == "S" {
                secs = Int(current) ?? 0; current = ""
            }
        }
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Formats a raw view count string ("1400000000") to a readable form ("1.4B views").
    /// If the string is already formatted (not a plain number), returns it as-is.
    static func formatViewCount(_ raw: String) -> String {
        guard let count = Int(raw) else {
            return raw
        }
        switch count {
        case 1_000_000_000...:
            return String(format: "%.1fB views", Double(count) / 1e9)
        case 1_000_000...:
            return String(format: "%.1fM views", Double(count) / 1e6)
        case 1_000...:
            return String(format: "%.0fK views", Double(count) / 1e3)
        default:
            return "\(count) views"
        }
    }
}
