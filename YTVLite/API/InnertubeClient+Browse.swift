import Foundation

// MARK: - Browse

extension InnertubeClient {
    func sendVote(
        endpoint: String,
        videoId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self.postVote(
                    endpoint: endpoint,
                    videoId: videoId,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    func authenticatedBrowse(
        browseId: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeBrowse(
                    browseId: browseId,
                    continuation: nil,
                    token: token,
                    completion: completion
                )
            }
        }
    }

    func executeWebBrowse(
        browseId: String?,
        continuation: String?,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = webContext
        if let cont = continuation {
            body["continuation"] = cont
        } else if let bid = browseId {
            body["browseId"] = bid
        }
        let headers = webBrowseHeaders(token: token)
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: headers,
            logTag: "webBrowse"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parseWebBrowsePage(json)
            let label = browseId ?? "continuation"
            if page.videos.isEmpty {
                let keys = json.keys.joined(separator: ", ")
                AppLog.innertube(
                    "web browse '\(label)': 0 videos. topKeys=[\(keys)]"
                )
            } else {
                AppLog.innertube(
                    "web browse '\(label)': \(page.videos.count) videos"
                )
            }
            return page
        } completion: { completion($0) }
    }

    func executeTVHistoryBrowse(
        token: String,
        continuation: String?,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        if let cont = continuation {
            body["continuation"] = cont
        } else {
            body[JSONKey.browseId] = BrowseID.history
        }
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "tvHistory"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parseTVHistoryPage(json)
            let hasCont = page.continuation != nil
            AppLog.innertube(
                "TV history: \(page.videos.count) videos, cont=\(hasCont)"
            )
            return page
        } completion: { completion($0) }
    }

    func executeBrowseAnonymous(
        browseId: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        body["browseId"] = browseId
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: anonHeaders(),
            logTag: "browseAnon(\(browseId))"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parsePageJSON(json)
            if page.videos.isEmpty {
                AppLog.innertube(
                    "executeBrowseAnonymous: empty for browseId=\(browseId)"
                )
                return nil
            }
            return page
        } completion: { completion($0) }
    }

    func executeBrowse(
        browseId: String?,
        continuation: String?,
        token: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        var body = tvContext
        if let cont = continuation {
            body["continuation"] = cont
        } else if let bid = browseId {
            body["browseId"] = bid
        }
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "browse(\(browseId ?? "cont"))"
        ) { json -> FeedPage? in
            let page = InnertubeClient.parsePageJSON(json)
            return page.videos.isEmpty ? nil : page
        } completion: { completion($0) }
    }
}

// MARK: - Private Browse Helpers

private extension InnertubeClient {
    func postVote(
        endpoint: String,
        videoId: String,
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var body = tvContext
        body["target"] = ["videoId": videoId]
        let headers: [String: String] = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.authorization: "Bearer \(token)",
            HTTPHeader.xYoutubeClientName: "7",
            HTTPHeader.xYoutubeClientVersion: "7.20260311.12.00"
        ]
        AppLog.innertube(
            "sendVote '\(endpoint)' videoId=\(videoId)"
        )
        execute(
            urlString: "\(baseURL)/\(endpoint)",
            body: body,
            headers: headers,
            logTag: "vote(\(endpoint))"
        ) { _ -> Void? in
            AppLog.innertube("sendVote '\(endpoint)' success")
            return ()
        } completion: { completion($0) }
    }

    func webBrowseHeaders(token: String) -> [String: String] {
        [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.authorization: "Bearer \(token)",
            HTTPHeader.xYoutubeClientName: "1",
            HTTPHeader.xYoutubeClientVersion: "2.20260206.01.00",
            HTTPHeader.userAgent: UserAgent.chromeDesktop,
            HTTPHeader.origin: AppURLs.YouTube.base,
            HTTPHeader.referer: AppURLs.YouTube.base + "/"
        ]
    }
}
