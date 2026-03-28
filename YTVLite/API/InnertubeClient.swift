import Foundation

final class InnertubeClient: VideoService {
    let api = APIClient()
    let session = InnertubeSession()

    var baseURL: String { session.baseURL }
    var webContext: [String: Any] { session.webContext }
    var tvContext: [String: Any] { session.tvContext }
}

// MARK: - VideoService

extension InnertubeClient {
    func fetchHomeFeed(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        if OAuthClient.shared.isAnonymous {
            executeBrowseAnonymous(browseId: BrowseID.home, completion: completion)
        } else {
            authenticatedBrowse(browseId: BrowseID.home, completion: completion)
        }
    }

    func fetchSubscriptionFeed(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        authenticatedBrowse(browseId: BrowseID.subscriptions, completion: completion)
    }

    func fetchHistory(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        withValidToken(completion: completion) { client, token in
            client.executeTVHistoryBrowse(token: token, continuation: nil, completion: completion)
        }
    }

    func fetchHistoryNextPage(
        continuation: String,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        executeTVHistoryBrowse(token: token, continuation: continuation, completion: completion)
    }

    func fetchPlaylists(completion: @escaping (Result<[Playlist], Error>) -> Void) {
        withValidToken(completion: completion) { client, token in
            client.executePlaylistsFetch(token: token, completion: completion)
        }
    }

    func fetchPlaylistVideos(
        playlistId: String,
        completion: @escaping (Result<[Video], Error>) -> Void
    ) {
        withValidToken(completion: completion) { client, token in
            client.executePlaylistVideosFetch(
                playlistId: playlistId,
                token: token,
                completion: completion
            )
        }
    }

    /// Fetches the signed-in account info via Innertube.
    func fetchAccountInfo(
        completion: @escaping (Result<(name: String, avatarURL: String?), Error>) -> Void
    ) {
        withValidToken(completion: completion) { client, token in
            client.executeAccountsList(token: token, completion: completion)
        }
    }

    func fetchNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        withValidToken(completion: completion) { client, token in
            client.executeBrowse(
                browseId: nil,
                continuation: continuation,
                token: token,
                completion: completion
            )
        }
    }

    func search(
        query: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<[Video], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)/search") else {
            completion(.failure(APIError.invalidURL))
            return
        }
        var body = webContext
        body["query"] = query
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        let headers = [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON]
        api.post(
            url: url,
            body: bodyData,
            headers: headers,
            cancellationToken: cancellationToken
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let data):
                completion(.success(InnertubeClient.parseSearchFeed(data)))
            }
        }
    }

    func fetchChannelInfo(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                AppLog.innertube("fetchChannelInfo failure \(channelId): \(error)")
                completion(.failure(error))
            case .success(let token):
                self?.executeChannelBrowse(
                    channelId: channelId,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    func fetchChannelPage(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        AppLog.innertube("fetchChannelPage start: \(channelId)")
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                AppLog.innertube("fetchChannelPage failure \(channelId): \(error)")
                completion(.failure(error))
            case .success(let token):
                self?.executeChannelPageBrowse(
                    channelId: channelId,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    func sendLike(videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendVote(endpoint: "like/like", videoId: videoId, completion: completion)
    }

    func sendDislike(videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendVote(endpoint: "like/dislike", videoId: videoId, completion: completion)
    }

    func removeLike(videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendVote(endpoint: "like/removelike", videoId: videoId, completion: completion)
    }

    func subscribeToChannel(
        channelId: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        withValidToken(completion: completion) { client, token in
            client.executeSubscribe(
                channelId: channelId,
                token: token,
                cancellationToken: cancellationToken,
                completion: completion
            )
        }
    }

    func unsubscribeFromChannel(
        channelId: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        withValidToken(completion: completion) { client, token in
            client.executeUnsubscribe(
                channelId: channelId,
                token: token,
                cancellationToken: cancellationToken,
                completion: completion
            )
        }
    }

    func fetchWatchPage(
        video: Video,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        AppLog.innertube("fetchWatchPage start: \(video.id)")
        if OAuthClient.shared.isSignedIn {
            OAuthClient.shared.validToken { [weak self] result in
                guard cancellationToken?.isCancelled != true else {
                    return
                }
                switch result {
                case .failure(let error):
                    AppLog.innertube("fetchWatchPage failure \(video.id): \(error)")
                    completion(.failure(error))
                case .success(let token):
                    self?.executeWatchNext(
                        video: video,
                        token: token,
                        cancellationToken: cancellationToken,
                        completion: completion
                    )
                }
            }
        } else {
            executeWatchNext(
                video: video,
                token: "",
                anonymous: true,
                cancellationToken: cancellationToken,
                completion: completion
            )
        }
    }

    func fetchComments(
        videoId: String,
        continuation: String? = nil,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    ) {
        AppLog.innertube("fetchComments: \(videoId), cont: \(continuation != nil)")
        executeComments(
            videoId: videoId,
            continuation: continuation,
            cancellationToken: cancellationToken,
            completion: completion
        )
    }

    func debugFetchPlayer(videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        AppLog.innertube("debugFetchPlayer start: \(videoId)")
        withValidToken(completion: completion) { client, token in
            client.executePlayerDebug(videoId: videoId, token: token, completion: completion)
        }
    }

    func fetchDirectPlayback(
        videoId: String,
        client: DirectPlaybackClient = .androidVR,
        poToken: String? = nil,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        AppLog.innertube("fetchDirectPlayback: \(videoId), client: \(client)")
        if client.usesCookieAuth {
            cookieAuthPlayback(
                videoId: videoId,
                playbackClient: client,
                poToken: poToken,
                cancellation: cancellationToken,
                completion: completion
            )
        } else {
            oauthPlayback(
                videoId: videoId,
                playbackClient: client,
                poToken: poToken,
                cancellation: cancellationToken,
                completion: completion
            )
        }
    }
}

// MARK: - Private Helpers

private extension InnertubeClient {
    func withValidToken<T>(
        completion: @escaping (Result<T, Error>) -> Void,
        perform: @escaping (InnertubeClient, String) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                guard let self else {
                    return
                }
                perform(self, token)
            }
        }
    }
}
