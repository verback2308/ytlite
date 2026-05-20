import Foundation

private enum ChannelTabParams {
    static let playlists = "EglwbGF5bGlzdHPyBgQKAkIA"
}

extension InnertubeClient {
    func fetchChannelTab(
        channelId: String,
        params: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        executeChannelTabBrowse(
            channelId: channelId,
            params: params,
            completion: completion
        )
    }

    func fetchChannelTabNextPage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.continuation] = continuation
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelTabNext"
        ) { json -> FeedPage? in
            Self.parsePageJSON(json)
        } completion: { completion($0) }
    }

    func fetchChannelPlaylists(
        channelId: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.browseId] = channelId
        body[JSONKey.params] = ChannelTabParams.playlists
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelPlaylists(\(channelId))"
        ) { json -> [Playlist]? in
            Self.parseChannelPlaylists(json)
        } completion: { [weak self] result in
            self?.logChannelPlaylistsResult(result, channelId: channelId)
            completion(result)
        }
    }
}

private extension InnertubeClient {
    func executeChannelTabBrowse(
        channelId: String,
        params: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.browseId] = channelId
        body[JSONKey.params] = params
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelTab(\(channelId))"
        ) { json -> FeedPage? in
            Self.parseChannelTabPage(json)
        } completion: { [weak self] result in
            self?.logChannelTabResult(result, label: channelId)
            completion(result)
        }
    }

    func logChannelTabResult(
        _ result: Result<FeedPage, Error>,
        label: String
    ) {
        switch result {
        case .success(let page):
            let hasMore = page.continuation != nil
            AppLog.channel(
                "tab \(label): \(page.videos.count) videos cont=\(hasMore)"
            )
        case .failure(let error):
            AppLog.channel("tab \(label) failed: \(error)")
        }
    }

    func logChannelPlaylistsResult(
        _ result: Result<[Playlist], Error>,
        channelId: String
    ) {
        switch result {
        case .success(let playlists):
            AppLog.channel(
                "playlists \(channelId): \(playlists.count) items"
            )
        case .failure(let error):
            AppLog.channel("playlists \(channelId) failed: \(error)")
        }
    }
}
