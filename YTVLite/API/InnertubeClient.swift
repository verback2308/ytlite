import Foundation

final class InnertubeClient: VideoService {

    static let shared = InnertubeClient()

    let api = APIClient()
    let baseURL = "https://www.youtube.com/youtubei/v1"
    var webContext: [String: Any] { InnertubeContexts.web }
    var tvContext: [String: Any] { InnertubeContexts.tv }

    // MARK: - VideoService

    func fetchHomeFeed(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        if OAuthClient.shared.isAnonymous {
            executeBrowseAnonymous(browseId: "FEwhat_to_watch", completion: completion)
        } else {
            authenticatedBrowse(browseId: "FEwhat_to_watch", completion: completion)
        }
    }

    func fetchSubscriptionFeed(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        authenticatedBrowse(browseId: "FEsubscriptions", completion: completion)
    }

    func fetchHistory(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeTVHistoryBrowse(token: token, continuation: nil,
                                                                   completion: completion)
            }
        }
    }

    func fetchHistoryNextPage(continuation: String, token: String,
                              completion: @escaping (Result<FeedPage, Error>) -> Void) {
        executeTVHistoryBrowse(token: token, continuation: continuation, completion: completion)
    }

    func fetchPlaylists(completion: @escaping (Result<[Playlist], Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executePlaylistsFetch(token: token, completion: completion)
            }
        }
    }

    func fetchPlaylistVideos(playlistId: String,
                             completion: @escaping (Result<[Video], Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token):
                self?.executePlaylistVideosFetch(playlistId: playlistId, token: token,
                                                 completion: completion)
            }
        }
    }

    /// Fetches the signed-in account info (display name + avatar URL) via Innertube
    /// /account/accounts_list — the same approach used by YouTube.js AccountManager.getInfo().
    func fetchAccountInfo(completion: @escaping (Result<(name: String, avatarURL: String?), Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeAccountsList(token: token, completion: completion)
            }
        }
    }

    func fetchNextPage(continuation: String, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeBrowse(browseId: nil, continuation: continuation,
                                                          token: token, completion: completion)
            }
        }
    }

    func search(query: String, completion: @escaping (Result<[Video], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/search") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = webContext
        body["query"] = query
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        api.post(url: url, headers: ["Content-Type": "application/json"], body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data): completion(.success(InnertubeClient.parseSearchFeed(data)))
            }
        }
    }

    func fetchChannelInfo(channelId: String, completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
       // print("[Innertube] fetchChannelInfo start: \(channelId)")
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                print("[Innertube] fetchChannelInfo token failure for \(channelId): \(error)")
                completion(.failure(error))
            case .success(let token):
                self?.executeChannelBrowse(channelId: channelId, token: token, completion: completion)
            }
        }
    }

    func fetchChannelPage(channelId: String, completion: @escaping (Result<ChannelPage, Error>) -> Void) {
        print("[Innertube] fetchChannelPage start: \(channelId)")
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                print("[Innertube] fetchChannelPage token failure for \(channelId): \(error)")
                completion(.failure(error))
            case .success(let token):
                self?.executeChannelPageBrowse(channelId: channelId, token: token, completion: completion)
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

    func subscribeToChannel(channelId: String, cancellationToken: CancellationToken? = nil,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeSubscribe(channelId: channelId, token: token,
                                                             cancellationToken: cancellationToken,
                                                             completion: completion)
            }
        }
    }

    func unsubscribeFromChannel(channelId: String, cancellationToken: CancellationToken? = nil,
                                completion: @escaping (Result<Void, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeUnsubscribe(channelId: channelId, token: token,
                                                               cancellationToken: cancellationToken,
                                                               completion: completion)
            }
        }
    }
    func fetchWatchPage(video: Video, cancellationToken: CancellationToken? = nil,
                        completion: @escaping (Result<WatchPage, Error>) -> Void) {
        print("[Innertube] fetchWatchPage start: \(video.id)")
        if OAuthClient.shared.isSignedIn {
            OAuthClient.shared.validToken { [weak self] result in
                guard cancellationToken?.isCancelled != true else { return }
                switch result {
                case .failure(let error):
                    print("[Innertube] fetchWatchPage token failure for \(video.id): \(error)")
                    completion(.failure(error))
                case .success(let token):
                    self?.executeWatchNext(video: video, token: token, cancellationToken: cancellationToken, completion: completion)
                }
            }
        } else {
            // Anonymous: call without auth token
            executeWatchNext(video: video, token: "", anonymous: true,
                             cancellationToken: cancellationToken, completion: completion)
        }
    }

    func fetchComments(videoId: String, continuation: String? = nil,
                       cancellationToken: CancellationToken? = nil,
                       completion: @escaping (Result<CommentsPage, Error>) -> Void) {
        print("[Innertube] fetchComments start: \(videoId), continuation: \(continuation != nil)")
        executeComments(videoId: videoId, continuation: continuation, cancellationToken: cancellationToken, completion: completion)
    }

    func debugFetchPlayer(videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        print("[Innertube] debugFetchPlayer start: \(videoId)")
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executePlayerDebug(videoId: videoId, token: token, completion: completion)
            }
        }
    }

    func fetchDirectPlayback(videoId: String, client: DirectPlaybackClient = .androidVR, poToken: String? = nil,
                             cancellationToken: CancellationToken? = nil,
                             completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        print("[Innertube] fetchDirectPlayback start: \(videoId), client: \(client)")

        if client.usesCookieAuth {
            fetchVisitorData(videoId: videoId, cancellationToken: cancellationToken) { [weak self] visitorData in
                guard cancellationToken?.isCancelled != true else { return }
                self?.executeDirectPlayback(videoId: videoId, client: client, token: "", poToken: poToken,
                                            visitorData: visitorData, cancellationToken: cancellationToken,
                                            completion: completion)
            }
            return
        }

        OAuthClient.shared.validToken { [weak self] result in
            guard cancellationToken?.isCancelled != true else { return }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeDirectPlayback(videoId: videoId, client: client, token: token, poToken: poToken,
                                            visitorData: nil, cancellationToken: cancellationToken,
                                            completion: completion)
            }
        }
    }

    /// Fetches the YouTube watch page to collect session cookies and extract visitorData.
    /// URLSession.shared automatically stores cookies for subsequent requests.
    private func fetchVisitorData(videoId: String, cancellationToken: CancellationToken? = nil,
                                  completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)&bpctr=9999999999&has_verified=1") else {
            completion(nil)
            return
        }
        print("[Innertube] fetching visitor data for \(videoId)...")
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-us,en;q=0.5", forHTTPHeaderField: "Accept-Language")

        // Set initial cookies like yt-dlp does
        let cookieProps1: [HTTPCookiePropertyKey: Any] = [
            .name: "PREF", .value: "hl=en&tz=UTC",
            .domain: ".youtube.com", .path: "/"
        ]
        let cookieProps2: [HTTPCookiePropertyKey: Any] = [
            .name: "SOCS", .value: "CAI",
            .domain: ".youtube.com", .path: "/"
        ]
        if let c1 = HTTPCookie(properties: cookieProps1) {
            HTTPCookieStorage.shared.setCookie(c1)
        }
        if let c2 = HTTPCookie(properties: cookieProps2) {
            HTTPCookieStorage.shared.setCookie(c2)
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("[Innertube] visitor data fetch failed: \(error.localizedDescription)")
                }
                completion(nil)
                return
            }

            // Log cookies received
            if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.youtube.com")!) {
                let names = cookies.map { $0.name }.joined(separator: ", ")
                print("[Innertube] cookies after preflight: \(names)")
            }

            var visitorData: String?
            if let data = data, let html = String(data: data, encoding: .utf8) {
                if let range = html.range(of: "\"VISITOR_DATA\":\""),
                   let endRange = html[range.upperBound...].range(of: "\"") {
                    visitorData = String(html[range.upperBound..<endRange.lowerBound])
                    print("[Innertube] extracted visitorData from ytcfg: \(visitorData?.prefix(30) ?? "nil")...")
                }
            }

            if visitorData == nil {
                if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.youtube.com")!),
                   let visitorCookie = cookies.first(where: { $0.name == "VISITOR_INFO1_LIVE" }),
                   let privacyCookie = cookies.first(where: { $0.name == "VISITOR_PRIVACY_METADATA" }) {
                    print("[Innertube] VISITOR_INFO1_LIVE=\(visitorCookie.value.prefix(20))..., VISITOR_PRIVACY_METADATA=\(privacyCookie.value.prefix(20))...")
                }
            }

            completion(visitorData)
        }
        cancellationToken?.register(task)
        task.resume()
    }

}
