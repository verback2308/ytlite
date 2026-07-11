import Foundation

// MARK: - Default parameter convenience extensions

extension SearchService {
    func search(
        query: String,
        completion: @escaping (Result<SearchPage, Error>) -> Void
    ) {
        search(
            query: query,
            continuation: nil,
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
