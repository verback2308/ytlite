import Foundation

// MARK: - Channel

extension InnertubeClient {
    func executeChannelBrowse(
        channelId: String,
        token: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        executeChannelBrowse(
            channelId: channelId,
            token: token,
            context: tvContext,
            completion: completion
        )
    }

    func executeChannelBrowse(
        channelId: String,
        token: String,
        context: [String: Any],
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        var body = context
        body["browseId"] = channelId
        let clientName = Self.extractClientName(from: context)
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        execute(
            urlString: browseURL,
            body: body,
            headers: authHeaders(token: token),
            logTag: "channelBrowse(\(clientName),\(channelId))"
        ) { json -> ChannelInfo? in
            InnertubeClient.parseChannelInfo(
                json,
                fallbackChannelId: channelId
            )
        } completion: { completion($0) }
    }

    func executeChannelPageBrowse(
        channelId: String,
        token: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        let browseURL = "\(baseURL)\(InnertubeEndpoint.browse)"
        guard let url = URL(string: browseURL) else {
            completion(.failure(APIError.invalidURL))
            return
        }
        var tvBody = tvContext
        tvBody["browseId"] = channelId
        guard let tvData = try? JSONSerialization.data(
            withJSONObject: tvBody
        ) else {
            completion(.failure(APIError.decodingFailed))
            return
        }
        let webSnapshot = fireWebChannelRequest(
            url: url,
            channelId: channelId
        )
        api.post(
            url: url,
            body: tvData,
            headers: authHeaders(token: token)
        ) { result in
            Self.handleChannelPageResponse(
                result,
                channelId: channelId,
                webSnapshot: webSnapshot,
                completion: completion
            )
        }
    }
}

// MARK: - Private Channel Helpers

private extension InnertubeClient {
    typealias WebSnapshot = () -> Result<Data, Error>?

    static func extractClientName(
        from context: [String: Any]
    ) -> String {
        let ctx = context["context"] as? [String: Any]
        let client = ctx?["client"] as? [String: Any]
        return client?["clientName"] as? String ?? "unknown"
    }

    static func handleChannelPageResponse(
        _ result: Result<Data, Error>,
        channelId: String,
        webSnapshot: WebSnapshot,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        guard let tvInfo = parseTVChannelData(
            result,
            channelId: channelId
        ),
            let tvJson = parseTVJson(from: result)
        else {
            forwardChannelError(result, completion: completion)
            return
        }
        let page = parsePageJSON(tvJson)
        let subState = parseSubscribeState(tvJson)
        let finalInfo = mergeWebChannelInfo(
            tvInfo: tvInfo,
            channelId: channelId,
            webSnapshot: webSnapshot
        )
        logChannelResult(finalInfo)
        completion(
            .success(
                ChannelPage(
                    info: finalInfo,
                    videosPage: page,
                    subscribeButtonText: subState.text,
                    isSubscribed: subState.isSubscribed
                )
            )
        )
    }

    static func parseTVChannelData(
        _ result: Result<Data, Error>,
        channelId: String
    ) -> ChannelInfo? {
        guard let tvJson = parseTVJson(from: result) else {
            return nil
        }
        return parseChannelInfo(
            tvJson,
            fallbackChannelId: channelId
        )
    }

    static func parseTVJson(
        from result: Result<Data, Error>
    ) -> [String: Any]? {
        guard case .success(let tvData) = result else {
            return nil
        }
        return try? JSONSerialization.jsonObject(
            with: tvData
        ) as? [String: Any]
    }

    static func forwardChannelError(
        _ result: Result<Data, Error>,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        AppLog.innertube("channel page parse failed")
        if case .failure(let err) = result {
            completion(.failure(err))
        } else {
            completion(.failure(APIError.decodingFailed))
        }
    }

    static func mergeWebChannelInfo(
        tvInfo: ChannelInfo,
        channelId: String,
        webSnapshot: WebSnapshot
    ) -> ChannelInfo {
        guard case .success(let wData) = webSnapshot(),
              let wJson = try? JSONSerialization.jsonObject(
                  with: wData
              ) as? [String: Any],
              let webInfo = parseChannelInfo(
                  wJson,
                  fallbackChannelId: channelId
              )
        else {
            return tvInfo
        }
        return ChannelInfo(
            id: tvInfo.id,
            title: tvInfo.title.isEmpty ? webInfo.title : tvInfo.title,
            avatarURL: tvInfo.avatarURL ?? webInfo.avatarURL,
            subscriberCountText: webInfo.subscriberCountText
                ?? tvInfo.subscriberCountText,
            bannerURL: webInfo.bannerURL ?? tvInfo.bannerURL,
            isVerified: webInfo.isVerified || tvInfo.isVerified,
            description: webInfo.description,
            contactInfo: webInfo.contactInfo,
            videoCountText: webInfo.videoCountText
        )
    }

    static func logChannelResult(_ info: ChannelInfo) {
        let subs = info.subscriberCountText ?? "nil"
        let hasBanner = info.bannerURL != nil
        AppLog.channel(
            "parsed: title='\(info.title)' subs='\(subs)' "
                + "banner=\(hasBanner) verified=\(info.isVerified)"
        )
    }

    func fireWebChannelRequest(
        url: URL,
        channelId: String
    ) -> WebSnapshot {
        var webBody = webContext
        webBody["browseId"] = channelId
        let webData = try? JSONSerialization.data(
            withJSONObject: webBody
        )
        let lock = NSLock()
        var webResult: Result<Data, Error>?
        var webDone = false
        if let webData {
            api.post(
                url: url,
                body: webData,
                headers: anonHeaders()
            ) { result in
                lock.lock()
                webResult = result
                webDone = true
                lock.unlock()
            }
        }
        return {
            lock.lock()
            let snapshot = webDone ? webResult : nil
            lock.unlock()
            return snapshot
        }
    }
}
