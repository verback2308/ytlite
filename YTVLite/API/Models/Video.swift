import Foundation

struct Video {
    let id: String
    let title: String
    let channelId: String?
    let channelName: String
    let channelAvatarURL: String?
    let thumbnailURL: String
    let viewCount: String?
    let publishedAt: String?
    let duration: String?
}

struct ChannelInfo {
    let id: String
    let title: String
    let avatarURL: String?
    let subscriberCountText: String?
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
        queue.async {
            if let cached = self.cache[channelId] {
                print("[ChannelInfoStore] cache hit for \(channelId)")
                DispatchQueue.main.async {
                    completion(.success(cached))
                }
                return
            }

            if self.pending[channelId] != nil {
                print("[ChannelInfoStore] joined pending request for \(channelId)")
                self.pending[channelId]?.append(completion)
                return
            }

            print("[ChannelInfoStore] fetching channel info for \(channelId)")
            self.pending[channelId] = [completion]

            self.client.fetchChannelInfo(channelId: channelId) { result in
                self.queue.async {
                    if case .success(let info) = result {
                        print("[ChannelInfoStore] fetched \(channelId), avatar: \(info.avatarURL ?? "nil"), title: \(info.title)")
                        self.cache[channelId] = info
                    } else if case .failure(let error) = result {
                        print("[ChannelInfoStore] failed \(channelId): \(error)")
                    }

                    let callbacks = self.pending.removeValue(forKey: channelId) ?? []
                    DispatchQueue.main.async {
                        callbacks.forEach { $0(result) }
                    }
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
