import Foundation

struct FeedPage: Codable {
    let videos: [Video]
    let continuation: String?
}

protocol VideoService: AnyObject {
    // Feed
    func fetchHomeFeed(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchSubscriptionFeed(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchHistory(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchHistoryNextPage(continuation: String, token: String, completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchNextPage(continuation: String, completion: @escaping (Result<FeedPage, Error>) -> Void)

    // Search
    func search(query: String, completion: @escaping (Result<[Video], Error>) -> Void)

    // Playlists
    func fetchPlaylists(completion: @escaping (Result<[Playlist], Error>) -> Void)
    func fetchPlaylistVideos(playlistId: String, completion: @escaping (Result<[Video], Error>) -> Void)

    // Channel
    func fetchChannelInfo(channelId: String, completion: @escaping (Result<ChannelInfo, Error>) -> Void)
    func fetchChannelPage(channelId: String, completion: @escaping (Result<ChannelPage, Error>) -> Void)

    // Watch page & playback
    func fetchWatchPage(video: Video, cancellationToken: CancellationToken?, completion: @escaping (Result<WatchPage, Error>) -> Void)
    func fetchDirectPlayback(videoId: String, client: DirectPlaybackClient, poToken: String?, cancellationToken: CancellationToken?, completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void)
    func fetchComments(videoId: String, continuation: String?, cancellationToken: CancellationToken?, completion: @escaping (Result<CommentsPage, Error>) -> Void)

    // Actions
    func sendLike(videoId: String, completion: @escaping (Result<Void, Error>) -> Void)
    func sendDislike(videoId: String, completion: @escaping (Result<Void, Error>) -> Void)
    func removeLike(videoId: String, completion: @escaping (Result<Void, Error>) -> Void)
    func subscribeToChannel(channelId: String, cancellationToken: CancellationToken?, completion: @escaping (Result<Void, Error>) -> Void)
    func unsubscribeFromChannel(channelId: String, cancellationToken: CancellationToken?, completion: @escaping (Result<Void, Error>) -> Void)

    // Account
    func fetchAccountInfo(completion: @escaping (Result<(name: String, avatarURL: String?), Error>) -> Void)
}

// Default parameter values for protocol methods
extension VideoService {
    func fetchWatchPage(video: Video, completion: @escaping (Result<WatchPage, Error>) -> Void) {
        fetchWatchPage(video: video, cancellationToken: nil, completion: completion)
    }
    func fetchDirectPlayback(videoId: String, client: DirectPlaybackClient = .androidVR, poToken: String? = nil,
                             completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        fetchDirectPlayback(videoId: videoId, client: client, poToken: poToken, cancellationToken: nil, completion: completion)
    }
    func fetchComments(videoId: String, continuation: String? = nil,
                       completion: @escaping (Result<CommentsPage, Error>) -> Void) {
        fetchComments(videoId: videoId, continuation: continuation, cancellationToken: nil, completion: completion)
    }
    func subscribeToChannel(channelId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        subscribeToChannel(channelId: channelId, cancellationToken: nil, completion: completion)
    }
    func unsubscribeFromChannel(channelId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        unsubscribeFromChannel(channelId: channelId, cancellationToken: nil, completion: completion)
    }
}
