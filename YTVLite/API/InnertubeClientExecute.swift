import Foundation

extension InnertubeClient {

    // MARK: - Account

    func executeAccountsList(token: String,
                             completion: @escaping (Result<(name: String, avatarURL: String?), Error>) -> Void) {
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.accountList)",
            body: tvContext,
            headers: authHeaders(token: token),
            logTag: "accountsList"
        ) { json -> (name: String, avatarURL: String?)? in
            guard let info = InnertubeClient.parseAccountsListJSON(json) else {
                if let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let str = String(data: pretty, encoding: .utf8) {
                    AppLog.innertube("accountsList unknown structure:\n\(str.prefix(3000))")
                }
                return nil
            }
            AppLog.innertube("accountsList: name=\(info.name), avatar=\(info.avatarURL ?? "nil")")
            return info
        } completion: { completion($0) }
    }

    static func parseAccountsListJSON(_ json: [String: Any]) -> (name: String, avatarURL: String?)? {
        // Format 1: header.activeAccountHeaderRenderer (old TV response)
        if let r = (json["header"] as? [String: Any])?["activeAccountHeaderRenderer"] as? [String: Any],
           let name = (r["accountName"] as? [String: Any])?["simpleText"] as? String {
            let thumb = ((r["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            return (name, thumb)
        }

        // Format 2: contents[].accountSectionListRenderer.contents[].accountItemSectionRenderer
        //           .contents[].accountItem  (newer TV response observed in production)
        if let sections = json["contents"] as? [[String: Any]] {
            for section in sections {
                if let aslr = section["accountSectionListRenderer"] as? [String: Any],
                   let innerSections = aslr["contents"] as? [[String: Any]] {
                    for inner in innerSections {
                        if let aisr = inner["accountItemSectionRenderer"] as? [String: Any],
                           let items = aisr["contents"] as? [[String: Any]] {
                            for item in items {
                                if let ai = item["accountItem"] as? [String: Any] {
                                    let name = (ai["accountName"] as? [String: Any])?["simpleText"] as? String
                                        ?? (ai["accountByline"] as? [String: Any])?["simpleText"] as? String
                                        ?? ""
                                    let thumb = (ai["accountPhoto"] as? [String: Any]).flatMap {
                                        ($0["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
                                    }
                                    if !name.isEmpty { return (name, thumb) }
                                }
                            }
                        }
                    }
                }
            }
        }

        return deepSearchAccountInfo(in: json)
    }

    static func deepSearchAccountInfo(in value: Any) -> (name: String, avatarURL: String?)? {
        if let dict = value as? [String: Any] {
            if let result = extractAccountNameAndPhoto(from: dict) { return result }
            for v in dict.values {
                if let result = deepSearchAccountInfo(in: v) { return result }
            }
        } else if let arr = value as? [Any] {
            for item in arr {
                if let result = deepSearchAccountInfo(in: item) { return result }
            }
        }
        return nil
    }

    static func parseAccountSectionList(_ asl: [String: Any]) -> (name: String, avatarURL: String?)? {
        guard let items = asl["items"] as? [[String: Any]] else { return nil }
        for item in items {
            if let result = extractAccountNameAndPhoto(from: item) { return result }
        }
        return nil
    }

    static func extractAccountNameAndPhoto(from node: [String: Any]) -> (name: String, avatarURL: String?)? {
        guard let r = node["activeAccountHeaderRenderer"] as? [String: Any] else { return nil }
        guard let name = (r["accountName"] as? [String: Any])?["simpleText"] as? String else { return nil }
        let thumb = ((r["accountPhoto"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
        return (name, thumb)
    }

    // MARK: - Playlists

    func executePlaylistsFetch(token: String,
                               completion: @escaping (Result<[Playlist], Error>) -> Void) {
        var body = tvContext
        body[JSONKey.browseId] = BrowseID.library
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistsFetch"
        ) { json -> [Playlist]? in
            let tabs = ((json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any])?["content"] as? [String: Any]
            let sections = ((tabs?["tvSecondaryNavRenderer"] as? [String: Any])?["sections"] as? [[String: Any]]) ?? []
            let allTabs = sections.first.flatMap {
                ($0["tvSecondaryNavSectionRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]]
            } ?? []
            return allTabs.compactMap { tab -> Playlist? in
                guard let tr = tab["tabRenderer"] as? [String: Any],
                      let title = tr["title"] as? String,
                      let params = (tr["endpoint"] as? [String: Any]).flatMap({
                          ($0["browseEndpoint"] as? [String: Any])?["params"] as? String
                      }),
                      let playlistId = Self.extractPlaylistIdFromParams(params)
                else { return nil }
                return Playlist(id: playlistId, title: title, description: "", thumbnailURL: nil, itemCount: nil)
            }
        } completion: { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let playlists):
                let wl = Playlist(id: "WL", title: "Watch Later", description: "", thumbnailURL: nil, itemCount: nil)
                let all = [wl] + playlists
                guard !all.isEmpty else { completion(.success(all)); return }
                let group = DispatchGroup()
                var thumbnails: [String: String] = [:]
                let lock = NSLock()
                for playlist in all {
                    group.enter()
                    self.fetchPlaylistFirstThumbnail(playlistId: playlist.id, token: token) { url in
                        if let url { lock.lock(); thumbnails[playlist.id] = url; lock.unlock() }
                        group.leave()
                    }
                }
                group.notify(queue: .global()) {
                    let withThumbs = all.map { p in
                        Playlist(id: p.id, title: p.title, description: p.description,
                                 thumbnailURL: thumbnails[p.id], itemCount: p.itemCount)
                    }
                    completion(.success(withThumbs))
                }
            }
        }
    }

    private static func extractPlaylistIdFromParams(_ params: String) -> String? {
        guard let urlDecoded = params.removingPercentEncoding,
              let data = Data(base64Encoded: urlDecoded, options: .ignoreUnknownCharacters)
        else { return nil }
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            var tag: UInt64 = 0; var shift = 0
            while i < bytes.count {
                let b = bytes[i]; i += 1
                tag |= UInt64(b & 0x7f) << shift; shift += 7
                if b & 0x80 == 0 { break }
            }
            let fieldNum = tag >> 3; let wireType = tag & 0x7
            switch wireType {
            case 0: while i < bytes.count { let b = bytes[i]; i += 1; if b & 0x80 == 0 { break } }
            case 2:
                guard i < bytes.count else { return nil }
                let len = Int(bytes[i]); i += 1
                guard i + len <= bytes.count else { return nil }
                if fieldNum == 70,
                   let id = String(bytes: bytes[i..<i+len], encoding: .utf8),
                   id.hasPrefix("PL") || id == "LL" { return id }
                i += len
            default: return nil
            }
        }
        return nil
    }

    func executePlaylistVideosFetch(playlistId: String, token: String,
                                    completion: @escaping (Result<[Video], Error>) -> Void) {
        var body = tvContext
        body["browseId"] = "VL\(playlistId)"
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistVideos(\(playlistId))"
        ) { json -> [Video]? in
            let rightColumn = ((json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any])?["content"] as? [String: Any]
            let surface = (rightColumn?["tvSurfaceContentRenderer"] as? [String: Any])?["content"] as? [String: Any]
            let twoCol = surface?["twoColumnRenderer"] as? [String: Any]
            let items = ((twoCol?["rightColumn"] as? [String: Any])?["playlistVideoListRenderer"] as? [String: Any])?["contents"] as? [[String: Any]] ?? []
            let videos: [Video] = items.compactMap { item -> Video? in
                guard let tile = item["tileRenderer"] as? [String: Any],
                      let thr = (tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any],
                      thr["thumbnailOverlays"] != nil
                else { return nil }
                return InnertubeClient.parseTileRenderer(tile)
            }
            AppLog.innertube("playlist \(playlistId): \(videos.count) videos")
            return videos.isEmpty ? nil : videos
        } completion: { completion($0) }
    }

    // MARK: - Votes / Likes

    func sendVote(endpoint: String, videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token):
                var body = self.tvContext
                body["target"] = ["videoId": videoId]
                let headers: [String: String] = [
                    HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
                    HTTPHeader.authorization: "Bearer \(token)",
                    HTTPHeader.xYoutubeClientName: "7",
                    HTTPHeader.xYoutubeClientVersion: "7.20260311.12.00",
                ]
                AppLog.innertube("sendVote '\(endpoint)' videoId=\(videoId)")
                self.execute(
                    urlString: "\(self.baseURL)/\(endpoint)",
                    body: body,
                    headers: headers,
                    logTag: "vote(\(endpoint))"
                ) { _ -> Void? in
                    AppLog.innertube("sendVote '\(endpoint)' success")
                    return ()
                } completion: { completion($0) }
            }
        }
    }

    // MARK: - Browse (authenticated)

    func authenticatedBrowse(browseId: String, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeBrowse(browseId: browseId, continuation: nil,
                                                          token: token, completion: completion)
            }
        }
    }

    func executeWebBrowse(browseId: String?, continuation: String?, token: String,
                          completion: @escaping (Result<FeedPage, Error>) -> Void) {
        var body = webContext
        if let c = continuation { body["continuation"] = c } else if let b = browseId { body["browseId"] = b }
        let headers: [String: String] = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.authorization: "Bearer \(token)",
            HTTPHeader.xYoutubeClientName: "1",
            HTTPHeader.xYoutubeClientVersion: "2.20260206.01.00",
            HTTPHeader.userAgent: UserAgent.chromeDesktop,
            HTTPHeader.origin: AppURLs.YouTube.base,
            HTTPHeader.referer: AppURLs.YouTube.base + "/"
        ]
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.browse)", body: body, headers: headers, logTag: "webBrowse") { json -> FeedPage? in
            let page = InnertubeClient.parseWebBrowsePage(json)
            if page.videos.isEmpty {
                AppLog.innertube("web browse '\(browseId ?? "continuation")': 0 videos. topKeys=[\(json.keys.joined(separator: ", "))]")
            } else {
                AppLog.innertube("web browse '\(browseId ?? "continuation")': \(page.videos.count) videos")
            }
            return page
        } completion: { completion($0) }
    }

    func executeTVHistoryBrowse(token: String, continuation: String?,
                                completion: @escaping (Result<FeedPage, Error>) -> Void) {
        var body = tvContext
        if let c = continuation { body["continuation"] = c } else { body[JSONKey.browseId] = BrowseID.history }
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.browse)", body: body, headers: authHeaders(token: token),
                logTag: "tvHistory") { json -> FeedPage? in
            let page = InnertubeClient.parseTVHistoryPage(json)
            AppLog.innertube("TV history: \(page.videos.count) videos, cont=\(page.continuation != nil)")
            return page
        } completion: { completion($0) }
    }

    func executeBrowseAnonymous(browseId: String, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        var body = tvContext
        body["browseId"] = browseId
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.browse)", body: body, headers: anonHeaders(),
                logTag: "browseAnon(\(browseId))") { json -> FeedPage? in
            let page = InnertubeClient.parsePageJSON(json)
            if page.videos.isEmpty {
                AppLog.innertube("executeBrowseAnonymous: empty result for browseId=\(browseId)")
                return nil
            }
            return page
        } completion: { completion($0) }
    }

    func executeBrowse(browseId: String?, continuation: String?, token: String,
                       completion: @escaping (Result<FeedPage, Error>) -> Void) {
        var body = tvContext
        if let c = continuation { body["continuation"] = c } else if let b = browseId { body["browseId"] = b }
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.browse)", body: body, headers: authHeaders(token: token),
                logTag: "browse(\(browseId ?? "cont"))") { json -> FeedPage? in
            let page = InnertubeClient.parsePageJSON(json)
            return page.videos.isEmpty ? nil : page
        } completion: { completion($0) }
    }

    // MARK: - Channel

    func executeChannelBrowse(channelId: String, token: String,
                               completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
        executeChannelBrowse(channelId: channelId, token: token, context: tvContext, completion: completion)
    }

    func executeChannelBrowse(channelId: String, token: String, context: [String: Any],
                               completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
        var body = context
        body["browseId"] = channelId
        let clientName = (((context["context"] as? [String: Any])?["client"] as? [String: Any])?["clientName"] as? String) ?? "unknown"
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.browse)", body: body, headers: authHeaders(token: token),
                logTag: "channelBrowse(\(clientName),\(channelId))") { json -> ChannelInfo? in
            InnertubeClient.parseChannelInfo(json, fallbackChannelId: channelId)
        } completion: { completion($0) }
    }

    func executeChannelPageBrowse(channelId: String, token: String,
                                  completion: @escaping (Result<ChannelPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)\(InnertubeEndpoint.browse)") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var tvBody = tvContext; tvBody["browseId"] = channelId
        var webBody = webContext; webBody["browseId"] = channelId

        guard let tvBodyData = try? JSONSerialization.data(withJSONObject: tvBody) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let webBodyData = try? JSONSerialization.data(withJSONObject: webBody)

        // Fire web request in parallel (non-blocking — used only if it finishes before TV)
        let lock = NSLock()
        var webResult: Result<Data, Error>?
        var webDone = false
        if let webData = webBodyData {
            api.post(url: url, headers: anonHeaders(), body: webData) { result in
                lock.lock(); webResult = result; webDone = true; lock.unlock()
            }
        }

        api.post(url: url, headers: authHeaders(token: token), body: tvBodyData) { result in
            guard case .success(let tvData) = result,
                  let tvJson = try? JSONSerialization.jsonObject(with: tvData) as? [String: Any],
                  let tvInfo = InnertubeClient.parseChannelInfo(tvJson, fallbackChannelId: channelId)
            else {
                AppLog.innertube("channel page parse failed for \(channelId)")
                if case .failure(let err) = result { completion(.failure(err)) }
                else { completion(.failure(APIError.decodingFailed)) }
                return
            }
            let page = InnertubeClient.parsePageJSON(tvJson)
            let subscribeState = InnertubeClient.parseSubscribeState(tvJson)
            lock.lock(); let webSnapshot = webDone ? webResult : nil; lock.unlock()
            var finalInfo = tvInfo
            if case .success(let wData) = webSnapshot,
               let wJson = try? JSONSerialization.jsonObject(with: wData) as? [String: Any],
               let webInfo = InnertubeClient.parseChannelInfo(wJson, fallbackChannelId: channelId) {
                finalInfo = ChannelInfo(
                    id: tvInfo.id,
                    title: tvInfo.title.isEmpty ? webInfo.title : tvInfo.title,
                    avatarURL: tvInfo.avatarURL ?? webInfo.avatarURL,
                    subscriberCountText: webInfo.subscriberCountText ?? tvInfo.subscriberCountText,
                    bannerURL: webInfo.bannerURL ?? tvInfo.bannerURL,
                    isVerified: webInfo.isVerified || tvInfo.isVerified,
                    description: webInfo.description,
                    contactInfo: webInfo.contactInfo,
                    videoCountText: webInfo.videoCountText
                )
            }
            AppLog.channel("parsed: title='\(finalInfo.title)' subs='\(finalInfo.subscriberCountText ?? "nil")' banner=\(finalInfo.bannerURL != nil) verified=\(finalInfo.isVerified)")
            completion(.success(ChannelPage(info: finalInfo, videosPage: page,
                                            subscribeButtonText: subscribeState.text,
                                            isSubscribed: subscribeState.isSubscribed)))
        }
    }

    // MARK: - Watch / Next

    func executeWatchNext(video: Video, token: String,
                          anonymous: Bool = false,
                          cancellationToken: CancellationToken? = nil,
                          completion: @escaping (Result<WatchPage, Error>) -> Void) {
        var body = anonymous ? webContext : tvContext
        body["videoId"] = video.id
        var headers = anonHeaders()
        if !anonymous && !token.isEmpty { headers[HTTPHeader.authorization] = "Bearer \(token)" }
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.next)", body: body, headers: headers,
                cancellationToken: cancellationToken, logTag: "watchNext(\(video.id))") { json -> WatchPage? in
            InnertubeClient.parseWatchPage(json, fallbackVideo: video)
        } completion: { completion($0) }
    }

    // MARK: - Comments

    func executeComments(videoId: String, continuation: String?,
                         cancellationToken: CancellationToken? = nil,
                         completion: @escaping (Result<CommentsPage, Error>) -> Void) {
        var body = webContext
        body["continuation"] = continuation ?? Self.buildCommentsContinuation(videoId: videoId, sortBy: 0, commentId: nil)
        let headers: [String: String] = [
            HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON,
            HTTPHeader.xYoutubeClientName: DirectPlaybackClient.web.clientHeaderName,
            HTTPHeader.xYoutubeClientVersion: DirectPlaybackClient.web.clientVersion
        ]
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.next)", body: body, headers: headers,
                cancellationToken: cancellationToken, logTag: "comments(\(videoId))") { json -> CommentsPage? in
            Self.parseCommentsPage(json)
        } completion: { completion($0) }
    }

    // MARK: - Player debug

    func executePlayerDebug(videoId: String, token: String,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        let contexts: [(name: String, body: [String: Any], auth: Bool)] = [
            ("TVHTML5", tvContext, true),
            ("WEB",     webContext, false)
        ]
        let group = DispatchGroup()
        var firstError: Error?
        for context in contexts {
            group.enter()
            executePlayer(videoId: videoId, contextName: context.name, context: context.body,
                          token: context.auth ? token : nil) { result in
                if case .failure(let e) = result, firstError == nil { firstError = e }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            completion(firstError.map { .failure($0) } ?? .success(()))
        }
    }

    // MARK: - Direct playback

    func executeDirectPlayback(videoId: String, client: DirectPlaybackClient, token: String, poToken: String?,
                               visitorData: String? = nil,
                               cancellationToken: CancellationToken? = nil,
                               completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        var body = client.context
        body["videoId"] = videoId
        if client.requiresContentCheckFlags {
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
            body["playbackContext"] = ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]]
        }
        if let poToken, !poToken.isEmpty {
            body["serviceIntegrityDimensions"] = ["poToken": poToken]
        }
        let headers = client.apiHeaders(token: token, visitorData: visitorData)
        AppLog.innertube("directPlayback(\(client)): videoId=\(videoId) headers=\(headers.keys.sorted().joined(separator: ","))")
        execute(
            urlString: "\(baseURL)/player\(client.playerURLSuffix)",
            body: body,
            headers: headers,
            cancellationToken: cancellationToken,
            logTag: "directPlayback(\(client))"
        ) { json -> DirectPlaybackInfo? in
            guard let info = Self.parseDirectPlaybackInfo(json) else {
                if let errorObj = json["error"],
                   let d = try? JSONSerialization.data(withJSONObject: errorObj, options: .prettyPrinted),
                   let s = String(data: d, encoding: .utf8) {
                    AppLog.innertube("directPlayback error (\(client)): \(s)")
                }
                Self.logPlayerDebug(videoId: videoId, contextName: client.description, json: json)
                return nil
            }
            AppLog.innertube("directPlayback selected (\(client)) \(videoId): hls=\(info.hlsManifestURL != nil) prog=\(info.progressiveURL != nil) v+a=\(info.videoURL != nil && info.audioURL != nil)")
            return info
        } completion: { completion($0) }
    }

    func executePlayer(videoId: String, contextName: String, context: [String: Any], token: String?,
                       completion: @escaping (Result<Void, Error>) -> Void) {
        var body = context
        body["videoId"] = videoId
        if contextName != "TVHTML5" { body["contentCheckOk"] = true; body["racyCheckOk"] = true }
        var headers = anonHeaders()
        if contextName == "WEB" {
            headers[HTTPHeader.xYoutubeClientName] = DirectPlaybackClient.web.clientHeaderName
            headers[HTTPHeader.xYoutubeClientVersion] = DirectPlaybackClient.web.clientVersion
        }
        if let token { headers[HTTPHeader.authorization] = "Bearer \(token)" }
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.player)", body: body, headers: headers,
                logTag: "playerDebug(\(contextName))") { json -> Void? in
            Self.logPlayerDebug(videoId: videoId, contextName: contextName, json: json)
            return ()
        } completion: { completion($0) }
    }

    // MARK: - Subscriptions

    func executeSubscribe(channelId: String, token: String, cancellationToken: CancellationToken? = nil,
                          completion: @escaping (Result<Void, Error>) -> Void) {
        var body = tvContext; body["channelIds"] = [channelId]
        AppLog.innertube("executeSubscribe channelId=\(channelId)")
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.subscribe)", body: body,
                headers: authHeaders(token: token), cancellationToken: cancellationToken,
                logTag: "subscribe(\(channelId))") { _ -> Void? in () } completion: { completion($0) }
    }

    func executeUnsubscribe(channelId: String, token: String, cancellationToken: CancellationToken? = nil,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        var body = tvContext; body["channelIds"] = [channelId]
        AppLog.innertube("executeUnsubscribe channelId=\(channelId)")
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.unsubscribe)", body: body,
                headers: authHeaders(token: token), cancellationToken: cancellationToken,
                logTag: "unsubscribe(\(channelId))") { _ -> Void? in () } completion: { completion($0) }
    }

    // MARK: - Private helpers

    private func fetchPlaylistFirstThumbnail(playlistId: String, token: String,
                                              completion: @escaping (String?) -> Void) {
        var body = tvContext; body["browseId"] = "VL\(playlistId)"
        execute(urlString: "\(baseURL)\(InnertubeEndpoint.browse)", body: body, headers: authHeaders(token: token),
                logTag: "playlistThumb(\(playlistId))") { json -> String? in
            let rightColumn = ((json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any])?["content"] as? [String: Any]
            let surface = (rightColumn?["tvSurfaceContentRenderer"] as? [String: Any])?["content"] as? [String: Any]
            let twoCol = surface?["twoColumnRenderer"] as? [String: Any]
            let items = ((twoCol?["rightColumn"] as? [String: Any])?["playlistVideoListRenderer"] as? [String: Any])?["contents"] as? [[String: Any]] ?? []
            for item in items {
                if let tile = item["tileRenderer"] as? [String: Any],
                   let video = InnertubeClient.parseTileRenderer(tile) { return video.thumbnailURL }
            }
            return nil
        } completion: { result in completion(try? result.get()) }
    }
}
