import Foundation

enum LikeStatus: String, Codable {
    case like = "LIKE"
    case dislike = "DISLIKE"
    case indifferent = "INDIFFERENT"
}

struct Video: Codable {
    let id: String
    let title: String
    let channelId: String?
    let channelName: String
    let channelAvatarURL: String?
    let thumbnailURL: String
    let viewCount: String?
    let publishedAt: String?
    let duration: String?
    let isLive: Bool

    init(id: String, title: String, channelId: String?, channelName: String,
         channelAvatarURL: String?, thumbnailURL: String, viewCount: String?,
         publishedAt: String?, duration: String?, isLive: Bool = false) {
        self.id = id
        self.title = title
        self.channelId = channelId
        self.channelName = channelName
        self.channelAvatarURL = channelAvatarURL
        self.thumbnailURL = thumbnailURL
        self.viewCount = viewCount
        self.publishedAt = publishedAt
        self.duration = duration
        self.isLive = isLive
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        channelName = try c.decode(String.self, forKey: .channelName)
        channelAvatarURL = try c.decodeIfPresent(String.self, forKey: .channelAvatarURL)
        thumbnailURL = try c.decode(String.self, forKey: .thumbnailURL)
        viewCount = try c.decodeIfPresent(String.self, forKey: .viewCount)
        publishedAt = try c.decodeIfPresent(String.self, forKey: .publishedAt)
        duration = try c.decodeIfPresent(String.self, forKey: .duration)
        isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
    }
}

struct ChannelInfo: Codable {
    let id: String
    let title: String
    let avatarURL: String?
    let subscriberCountText: String?
    let bannerURL: String?
    let isVerified: Bool
    let description: String?
    let contactInfo: String?
    let videoCountText: String?
}

struct ChannelPage {
    let info: ChannelInfo
    let videosPage: FeedPage
    let subscribeButtonText: String?
    let isSubscribed: Bool
}

struct WatchPage {
    let video: Video
    let description: String?
    let channelInfo: ChannelInfo?
    let subscribeButtonText: String?
    let isSubscribed: Bool
    let relatedVideos: [Video]
    let likeCount: String?
    let likeStatus: LikeStatus?
    let nextVideo: Video?
}

struct DashFormatInfo {
    let url: URL
    let itag: Int
    let mimeType: String       // e.g. "video/mp4; codecs=\"avc1.4d401f\""
    let codecs: String         // e.g. "avc1.4d401f"
    let bitrate: Int
    let contentLength: Int64
    let initRangeEnd: Int      // e.g. 739
    let indexRangeStart: Int   // e.g. 740
    let indexRangeEnd: Int     // e.g. 11739
    let width: Int?
    let height: Int?
    let fps: Int?
}

struct DirectPlaybackInfo {
    let hlsManifestURL: URL?
    let dashManifestURL: URL?
    let progressiveURL: URL?
    let videoURL: URL?
    let audioURL: URL?
    let serverAbrStreamingURL: URL?
    let videoPlaybackUstreamerConfig: String?
    let onesieUstreamerConfig: String?
    let sabrVideoFormat: SabrFormatInfo?
    let sabrAudioFormat: SabrFormatInfo?
    let videoItag: Int?
    let audioItag: Int?
    let qualityLabel: String?
    let visitorData: String?
    let hasVideoPlaybackUstreamerConfig: Bool
    let dashVideoFormat: DashFormatInfo?
    let dashAudioFormat: DashFormatInfo?
    let allDashVideoFormats: [DashFormatInfo]
    let duration: Double?
}

struct SabrFormatInfo {
    let itag: Int
    let lastModified: String?
    let xtags: String?
    let audioTrackId: String?
    let isDrc: Bool
    let mimeType: String?
    let bitrate: Int?
    let width: Int?
    let height: Int?
}

struct Comment {
    let id: String
    let authorName: String
    let authorChannelId: String?
    let authorAvatarURL: String?
    let content: String
    let publishedTime: String?
    let likeCount: String?
    let replyCount: String?
    let isPinned: Bool
}

struct CommentsPage {
    let title: String?
    let comments: [Comment]
    let continuation: String?
}

final class ChannelInfoStore {
    static let shared = ChannelInfoStore()

    private let client = InnertubeClient()
    private let queue = DispatchQueue(label: "com.ytvlite.channel-info-store")
    private var cache: [String: ChannelInfo] = [:]
    private var pending: [String: [(Result<ChannelInfo, Error>) -> Void]] = [:]

    private init() {}

    func fetch(channelId: String, completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
        // Fast-path: in-memory hit (main thread, zero cost)
        if Thread.isMainThread, let cached = cache[channelId] {
            completion(.success(cached))
            return
        }

        queue.async {
            // 1. In-memory cache
            if let cached = self.cache[channelId] {
                DispatchQueue.main.async { completion(.success(cached)) }
                return
            }

            // 2. Deduplicate: if a request is already in-flight, just queue the callback
            if self.pending[channelId] != nil {
                self.pending[channelId]?.append(completion)
                return
            }

            // 3. Disk cache (survives restarts) — only checked once per channel per session
            if let cached = AppCache.shared.cachedChannelInfo(channelId: channelId) {
                self.cache[channelId] = cached
                AppLog.channel("info disk-hit \(channelId) avatar=\(cached.avatarURL != nil ? "YES" : "NO")")
                DispatchQueue.main.async { completion(.success(cached)) }
                return
            }

            // 4. Network fetch
            self.pending[channelId] = [completion]
            AppLog.channel("info fetch \(channelId)")

            self.client.fetchChannelInfo(channelId: channelId) { result in
                self.queue.async {
                    if case .success(let info) = result {
                        self.cache[channelId] = info
                        AppCache.shared.setChannelInfo(info, channelId: channelId)
                    } else if case .failure(let error) = result {
                        AppLog.channel("info fetch failed \(channelId): \(error)")
                    }
                    let callbacks = self.pending.removeValue(forKey: channelId) ?? []
                    DispatchQueue.main.async { callbacks.forEach { $0(result) } }
                }
            }
        }
    }

    func preload(channelIds: [String]) {
        let uniqueIds = Array(Set(channelIds))
        uniqueIds.forEach { channelId in
            fetch(channelId: channelId) { _ in }
        }
    }
}
