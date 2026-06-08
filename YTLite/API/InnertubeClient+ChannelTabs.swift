import Foundation

enum ChannelTabParams {
    static let playlists = "EglwbGF5bGlzdHPyBgQKAkIA"
}

extension InnertubeClient {
    func fetchChannelTab(
        channelId: String,
        params: String,
        completion: @escaping (Result<ChannelTabPage, Error>) -> Void
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
            Self.parseChannelTabNextPage(json)
        } completion: { completion($0) }
    }

    func fetchChannelPlaylists(
        channelId: String,
        params: String = ChannelTabParams.playlists,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.browseId] = channelId
        body[JSONKey.params] = params
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelPlaylists(\(channelId))"
        ) { json -> PlaylistsPage? in
            Self.parseChannelPlaylists(json)
        } completion: { [weak self] result in
            self?.logChannelPlaylistsResult(result, channelId: channelId)
            completion(result)
        }
    }

    func fetchChannelPlaylistsNextPage(
        continuation: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.continuation] = continuation
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelPlaylistsNext"
        ) { json -> PlaylistsPage? in
            Self.parseChannelPlaylistsNextPage(json)
        } completion: { completion($0) }
    }
}

private extension InnertubeClient {
    func executeChannelTabBrowse(
        channelId: String,
        params: String,
        completion: @escaping (Result<ChannelTabPage, Error>) -> Void
    ) {
        var body = webContext
        body[JSONKey.browseId] = channelId
        body[JSONKey.params] = params
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: anonHeaders(),
            logTag: "channelTab(\(channelId))"
        ) { json -> ChannelTabPage? in
            Self.parseChannelTabPage(json)
        } completion: { [weak self] result in
            self?.logChannelTabResult(result, label: channelId)
            completion(result)
        }
    }

    func logChannelTabResult(
        _ result: Result<ChannelTabPage, Error>,
        label: String
    ) {
        switch result {
        case .success(let tabPage):
            let count = tabPage.feedPage.videos.count
            let hasMore = tabPage.feedPage.continuation != nil
            AppLog.channel(
                "tab \(label): \(count) videos cont=\(hasMore)"
            )
        case .failure(let error):
            AppLog.channel("tab \(label) failed: \(error)")
        }
    }

    func logChannelPlaylistsResult(
        _ result: Result<PlaylistsPage, Error>,
        channelId: String
    ) {
        switch result {
        case .success(let page):
            AppLog.channel(
                "playlists \(channelId): \(page.playlists.count) items"
            )
        case .failure(let error):
            AppLog.channel("playlists \(channelId) failed: \(error)")
        }
    }
}
