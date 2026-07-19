import Foundation

/// User-selectable search filters, encoded into the Innertube /search
/// `params` field (the same protobuf schema Invidious and yt-dlp use).
struct SearchFilters: Equatable {
    enum Sort: Int, CaseIterable {
        case relevance = 0
        case rating = 1
        case uploadDate = 2
        case viewCount = 3

        var displayName: String {
            switch self {
            case .relevance:
                return "相关"
            case .rating:
                return "评分"
            case .uploadDate:
                return "上传日期"
            case .viewCount:
                return "浏览次数"
            }
        }
    }

    enum UploadDate: Int, CaseIterable {
        case any = 0
        case lastHour = 1
        case today = 2
        case thisWeek = 3
        case thisMonth = 4
        case thisYear = 5

        var displayName: String {
            switch self {
            case .any:
                return "任何时间"
            case .lastHour:
                return "最后一小时"
            case .today:
                return "今天"
            case .thisWeek:
                return "本周"
            case .thisMonth:
                return "本月"
            case .thisYear:
                return "今年"
            }
        }
    }

    enum ContentType: Int, CaseIterable {
        case any = 0
        case video = 1
        case channel = 2
        case playlist = 3

        var displayName: String {
            switch self {
            case .any:
                return "任何类型"
            case .video:
                return "视频"
            case .channel:
                return "沟渠"
            case .playlist:
                return "播放曲目"
            }
        }
    }

    enum Duration: Int, CaseIterable {
        case any = 0
        case short = 1
        case long = 2
        case medium = 3

        var displayName: String {
            switch self {
            case .any:
                return "本年度"
            case .short:
                return "小于4分钟"
            case .long:
                return "结束20分钟"
            case .medium:
                return "4–20分钟"
            }
        }
    }

    var sort: Sort = .relevance
    var uploadDate: UploadDate = .any
    var type: ContentType = .any
    var duration: Duration = .any

    var isDefault: Bool { self == SearchFilters() }

    /// Base64 protobuf for the /search request; nil when nothing is set.
    /// Schema: field 1 varint = sort; field 2 message { 1 = upload date,
    /// 2 = type, 3 = duration }. Every value fits a single varint byte.
    var encodedParams: String? {
        guard !isDefault else {
            return nil
        }
        var bytes: [UInt8] = []
        if sort != .relevance {
            bytes += [0x08, UInt8(sort.rawValue)]
        }
        var inner: [UInt8] = []
        if uploadDate != .any {
            inner += [0x08, UInt8(uploadDate.rawValue)]
        }
        if type != .any {
            inner += [0x10, UInt8(type.rawValue)]
        }
        if duration != .any {
            inner += [0x18, UInt8(duration.rawValue)]
        }
        if !inner.isEmpty {
            bytes += [0x12, UInt8(inner.count)] + inner
        }
        return Data(bytes).base64EncodedString()
    }
}
