import Foundation

struct FeedPage: Codable {
    let videos: [Video]
    let continuation: String?
}

// MARK: - ISP-compliant service protocols
//
// Each protocol covers exactly one responsibility.
// ViewControllers depend only on the protocol they use, not the full VideoService.

protocol FeedService: AnyObject {
    func fetchHomeFeed(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchSubscriptionFeed(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
}

protocol HistoryService: AnyObject {
    func fetchHistory(
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchHistoryNextPage(
        continuation: String,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
}

protocol SearchService: AnyObject {
    func search(
        query: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<[Video], Error>) -> Void
    )
}

protocol PlaylistService: AnyObject {
    func fetchPlaylists(
        completion: @escaping (Result<[Playlist], Error>) -> Void
    )
    func fetchPlaylistVideos(
        playlistId: String,
        completion: @escaping (Result<[Video], Error>) -> Void
    )
}

protocol ChannelService: AnyObject {
    func fetchChannelInfo(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    )
    func fetchChannelPage(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    )
}

struct ChannelBrowseAction {
    let channelId: String
    let params: String
}

struct ChannelFilterChip {
    enum Action {
        case continuation(token: String)
        case browse(ChannelBrowseAction)
    }
    let label: String
    let action: Action
    var params: String {
        switch action {
        case .continuation(let token):
            return token
        case .browse(let browseAction):
            return browseAction.params
        }
    }
}

struct ChannelTabPage {
    let feedPage: FeedPage
    let filterChips: [ChannelFilterChip]
}

struct PlaylistsPage {
    let playlists: [Playlist]
    let continuation: String?
    var filterChips: [ChannelFilterChip] = []
}

protocol ChannelTabService: AnyObject {
    func fetchChannelTab(
        channelId: String,
        params: String,
        completion: @escaping (Result<ChannelTabPage, Error>) -> Void
    )
    func fetchChannelTabNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    )
    func fetchChannelPlaylists(
        channelId: String,
        params: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    )
    func fetchChannelPlaylistsNextPage(
        continuation: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    )
}

protocol WatchService: AnyObject {
    func fetchWatchPage(
        video: Video,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    )
    // swiftlint:disable:next function_parameter_count
    func fetchDirectPlayback(
        videoId: String,
        client: DirectPlaybackClient,
        poToken: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    )
    func fetchComments(
        videoId: String,
        continuation: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    )
    func fetchWatchtimeURLs(
        videoId: String,
        completion: @escaping (WatchtimeURLs?) -> Void
    )
}

protocol EngagementService: AnyObject {
    func sendLike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func sendDislike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func removeLike(
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func subscribeToChannel(
        channelId: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<Void, Error>) -> Void
    )
    func unsubscribeFromChannel(
        channelId: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

protocol AccountService: AnyObject {
    func fetchAccountInfo(
        completion: @escaping (
            Result<(name: String, avatarURL: String?), Error>
        ) -> Void
    )
}

// MARK: - Composite umbrella
typealias VideoService =
    FeedService & HistoryService & SearchService
    & PlaylistService & ChannelService & WatchService
    & EngagementService & AccountService

// MARK: - Default parameter convenience extensions

extension SearchService {
    func search(
        query: String,
        completion: @escaping (Result<[Video], Error>) -> Void
    ) {
        search(
            query: query,
            cancellationToken: nil,
            completion: completion
        )
    }
}

extension WatchService {
    func fetchWatchPage(
        video: Video,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        fetchWatchPage(
            video: video,
            cancellationToken: nil,
            completion: completion
        )
    }

    func fetchDirectPlayback(
        videoId: String,
        client: DirectPlaybackClient = .androidVR,
        poToken: String? = nil,
        completion: @escaping (
            Result<DirectPlaybackInfo, Error>
        ) -> Void
    ) {
        fetchDirectPlayback(
            videoId: videoId,
            client: client,
            poToken: poToken,
            cancellationToken: nil,
            completion: completion
        )
    }

    func fetchComments(
        videoId: String,
        continuation: String? = nil,
        completion: @escaping (
            Result<CommentsPage, Error>
        ) -> Void
    ) {
        fetchComments(
            videoId: videoId,
            continuation: continuation,
            cancellationToken: nil,
            completion: completion
        )
    }
}

extension EngagementService {
    func subscribeToChannel(
        channelId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        subscribeToChannel(
            channelId: channelId,
            cancellationToken: nil,
            completion: completion
        )
    }

    func unsubscribeFromChannel(
        channelId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        unsubscribeFromChannel(
            channelId: channelId,
            cancellationToken: nil,
            completion: completion
        )
    }
}
