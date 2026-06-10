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

    init(
        id: String,
        title: String,
        channelId: String?,
        channelName: String,
        channelAvatarURL: String?,
        thumbnailURL: String,
        viewCount: String?,
        publishedAt: String?,
        duration: String?,
        isLive: Bool = false
    ) {
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
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        channelId = try container.decodeIfPresent(String.self, forKey: .channelId)
        channelName = try container.decode(String.self, forKey: .channelName)
        channelAvatarURL = try container.decodeIfPresent(
            String.self, forKey: .channelAvatarURL
        )
        thumbnailURL = try container.decode(String.self, forKey: .thumbnailURL)
        viewCount = try container.decodeIfPresent(String.self, forKey: .viewCount)
        publishedAt = try container.decodeIfPresent(
            String.self, forKey: .publishedAt
        )
        duration = try container.decodeIfPresent(String.self, forKey: .duration)
        isLive = try container.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
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
    let hasPlaybackUstreamerConfig: Bool
    let dashVideoFormat: DashFormatInfo?
    let dashAudioFormat: DashFormatInfo?
    let allDashVideoFormats: [DashFormatInfo]
    let duration: Double?
    let playbackTrackingURLs: WatchtimeURLs?
    let captionTracks: [SubtitleTrack]
}

struct WatchtimeURLs {
    let playbackURL: String
    let watchtimeURL: String
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

    private var channelService: ChannelService?
    private let queue = DispatchQueue(label: "com.ytvlite.channel-info-store")
    private var cache: [String: ChannelInfo] = [:]
    private var pending: [String: [(Result<ChannelInfo, Error>) -> Void]] = [:]

    private init() {}

    func configure(channelService: ChannelService) {
        self.channelService = channelService
    }

    func fetch(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        // ALL cache/pending accesses must go through queue to
        // avoid data races on the dictionary.
        queue.async {
            if let cached = self.cache[channelId] {
                DispatchQueue.main.async {
                    completion(.success(cached))
                }
                return
            }

            if self.pending[channelId] != nil {
                self.pending[channelId]?.append(completion)
                return
            }

            if let cached = self.loadFromDisk(channelId: channelId) {
                DispatchQueue.main.async {
                    completion(.success(cached))
                }
                return
            }

            self.fetchFromNetwork(
                channelId: channelId,
                completion: completion
            )
        }
    }

    private func loadFromDisk(channelId: String) -> ChannelInfo? {
        guard let cached = AppCache.shared.cachedChannelInfo(channelId: channelId)
        else { return nil }
        cache[channelId] = cached
        let hasAvatar = cached.avatarURL != nil ? "YES" : "NO"
        AppLog.channel(
            "info disk-hit \(channelId) avatar=\(hasAvatar)"
        )
        return cached
    }

    private func fetchFromNetwork(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        guard let channelService else {
            assertionFailure("ChannelInfoStore is not configured")
            DispatchQueue.main.async {
                completion(.failure(APIError.invalidResponse))
            }
            return
        }
        pending[channelId] = [completion]
        AppLog.channel("info fetch \(channelId)")

        channelService.fetchChannelInfo(channelId: channelId) { result in
            self.queue.async {
                if case .success(let info) = result {
                    self.cache[channelId] = info
                    AppCache.shared.setChannelInfo(info, channelId: channelId)
                } else if case .failure(let error) = result {
                    AppLog.channel(
                        "info fetch failed \(channelId): \(error)"
                    )
                }
                let callbacks = self.pending.removeValue(forKey: channelId) ?? []
                DispatchQueue.main.async { callbacks.forEach { $0(result) } }
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
