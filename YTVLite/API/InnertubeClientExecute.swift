import Foundation

extension InnertubeClient {

    func executeAccountsList(token: String,
                                     completion: @escaping (Result<(name: String, avatarURL: String?), Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/account/accounts_list") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                if let info = InnertubeClient.parseAccountsListJSON(json) {
                    print("[Innertube] accountsList: name=\(info.name), avatar=\(info.avatarURL ?? "nil")")
                    completion(.success(info))
                } else {
                    if let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                       let str = String(data: pretty, encoding: .utf8) {
                        print("[Innertube] accountsList unknown structure:\n\(str.prefix(3000))")
                    }
                    completion(.failure(APIError.decodingFailed))
                }
            }
        }
    }

    /// Recursively searches for account name + photo in accounts_list / similar responses.
    static func parseAccountsListJSON(_ json: [String: Any]) -> (name: String, avatarURL: String?)? {
        // Try known explicit paths first
        // Path 1: header.activeAccountHeaderRenderer
        if let r = (json["header"] as? [String: Any])?["activeAccountHeaderRenderer"] as? [String: Any],
           let info = extractAccountNameAndPhoto(from: r) { return info }

        // Path 2: contents dict → accountSectionListRenderer
        if let contents = json["contents"] as? [String: Any] {
            if let asl = contents["accountSectionListRenderer"] as? [String: Any],
               let info = parseAccountSectionList(asl) { return info }
            if let info = extractAccountNameAndPhoto(from: contents) { return info }
        }

        // Path 3: contents array
        if let arr = json["contents"] as? [[String: Any]] {
            for item in arr {
                if let asl = item["accountSectionListRenderer"] as? [String: Any],
                   let info = parseAccountSectionList(asl) { return info }
                if let r = item["activeAccountHeaderRenderer"] as? [String: Any],
                   let info = extractAccountNameAndPhoto(from: r) { return info }
            }
        }

        // Path 4: top-level activeAccountHeaderRenderer
        if let r = json["activeAccountHeaderRenderer"] as? [String: Any],
           let info = extractAccountNameAndPhoto(from: r) { return info }

        // Fallback: deep recursive search for any node that has accountName
        return deepSearchAccountInfo(in: json)
    }

    /// Recursively walk the entire JSON tree looking for a node with accountName + accountPhoto.
    static func deepSearchAccountInfo(in value: Any) -> (name: String, avatarURL: String?)? {
        guard let dict = value as? [String: Any] else {
            if let arr = value as? [Any] {
                for item in arr {
                    if let result = deepSearchAccountInfo(in: item) { return result }
                }
            }
            return nil
        }
        // Check if this node has accountName
        if let info = extractAccountNameAndPhoto(from: dict) { return info }
        // Recurse into values
        for (key, val) in dict {
            // Skip responseContext (noisy, no useful data)
            if key == "responseContext" { continue }
            if let result = deepSearchAccountInfo(in: val) { return result }
        }
        return nil
    }

    static func parseAccountSectionList(_ asl: [String: Any]) -> (name: String, avatarURL: String?)? {
        let sections = asl["contents"] as? [[String: Any]] ?? []
        for section in sections {
            let ais = section["accountItemSectionRenderer"] as? [String: Any]
            let items = ais?["contents"] as? [[String: Any]] ?? []
            for item in items {
                if let account = item["accountItem"] as? [String: Any],
                   let info = extractAccountNameAndPhoto(from: account) { return info }
            }
        }
        return nil
    }

    static func extractAccountNameAndPhoto(from node: [String: Any]) -> (name: String, avatarURL: String?)? {
        // Try to get name from accountName or similar
        let nameNode = node["accountName"] as? [String: Any]
        let name = nameNode?["simpleText"] as? String
            ?? (nameNode?["runs"] as? [[String: Any]])?.first?["text"] as? String
            ?? node["title"] as? String
        guard let name = name, !name.isEmpty else { return nil }
        // Avatar from accountPhoto or thumbnail
        let photoNode = (node["accountPhoto"] ?? node["thumbnail"]) as? [String: Any]
        let thumbs = photoNode?["thumbnails"] as? [[String: Any]] ?? []
        let avatarURL = thumbs.last?["url"] as? String ?? thumbs.first?["url"] as? String
        return (name: name, avatarURL: avatarURL)
    }

    func executePlaylistsFetch(token: String,
                                       completion: @escaping (Result<[Playlist], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        body["browseId"] = "FEmy_youtube"
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let tabs = ((json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any])?["content"] as? [String: Any]
                let navRenderer = (tabs?["tvSecondaryNavRenderer"] as? [String: Any])
                let sections = navRenderer?["sections"] as? [[String: Any]] ?? []
                let allTabs = sections.first.flatMap {
                    ($0["tvSecondaryNavSectionRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]]
                } ?? []

                let playlists: [Playlist] = allTabs.compactMap { tab in
                    guard let tr = tab["tabRenderer"] as? [String: Any],
                          let title = tr["title"] as? String,
                          let params = (tr["endpoint"] as? [String: Any]).flatMap({
                              ($0["browseEndpoint"] as? [String: Any])?["params"] as? String
                          }),
                          let playlistId = Self.extractPlaylistIdFromParams(params)
                    else { return nil }
                    return Playlist(id: playlistId, title: title, description: "",
                                    thumbnailURL: nil, itemCount: nil)
                }
                print("[Innertube] playlists via FEmy_youtube: \(playlists.count)")

                // Include Watch Later in thumbnail batch
                let wl = Playlist(id: "WL", title: "Watch Later", description: "",
                                  thumbnailURL: nil, itemCount: nil)
                let allPlaylists = [wl] + playlists

                // Fetch thumbnails (first valid video thumbnail) in parallel
                guard !allPlaylists.isEmpty else { completion(.success(allPlaylists)); return }
                let group = DispatchGroup()
                var thumbnails: [String: String] = [:]
                let lock = NSLock()
                for playlist in allPlaylists {
                    group.enter()
                    self.fetchPlaylistFirstThumbnail(playlistId: playlist.id, token: token) { url in
                        if let url = url {
                            lock.lock(); thumbnails[playlist.id] = url; lock.unlock()
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .global()) {
                    let withThumbs = allPlaylists.map { p in
                        Playlist(id: p.id, title: p.title, description: p.description,
                                 thumbnailURL: thumbnails[p.id], itemCount: p.itemCount)
                    }
                    completion(.success(withThumbs))
                }
            }
        }
    }

    /// Decodes an Innertube browse params string (URL-encoded base64 protobuf)
    /// and extracts the playlist ID from field 70 (wiretype 2).
    private static func extractPlaylistIdFromParams(_ params: String) -> String? {
        guard let urlDecoded = params.removingPercentEncoding,
              let data = Data(base64Encoded: urlDecoded, options: .ignoreUnknownCharacters)
        else { return nil }
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            // Parse varint tag
            var tag: UInt64 = 0
            var shift = 0
            while i < bytes.count {
                let b = bytes[i]; i += 1
                tag |= UInt64(b & 0x7f) << shift
                shift += 7
                if b & 0x80 == 0 { break }
            }
            let fieldNum = tag >> 3
            let wireType = tag & 0x7
            switch wireType {
            case 0: // varint — skip
                while i < bytes.count { let b = bytes[i]; i += 1; if b & 0x80 == 0 { break } }
            case 2: // length-delimited
                guard i < bytes.count else { return nil }
                let len = Int(bytes[i]); i += 1
                guard i + len <= bytes.count else { return nil }
                if fieldNum == 70,
                   let id = String(bytes: bytes[i..<i+len], encoding: .utf8),
                   id.hasPrefix("PL") || id == "LL" {
                    return id
                }
                i += len
            default:
                return nil
            }
        }
        return nil
    }

    func executePlaylistVideosFetch(playlistId: String, token: String,
                                    completion: @escaping (Result<[Video], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        body["browseId"] = "VL\(playlistId)"
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let rightColumn = ((json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any])?["content"] as? [String: Any]
                let surface = (rightColumn?["tvSurfaceContentRenderer"] as? [String: Any])?["content"] as? [String: Any]
                let twoCol = surface?["twoColumnRenderer"] as? [String: Any]
                let playlistVL = (twoCol?["rightColumn"] as? [String: Any])?["playlistVideoListRenderer"] as? [String: Any]
                let items = playlistVL?["contents"] as? [[String: Any]] ?? []

                let videos: [Video] = items.compactMap { item in
                    guard let tile = item["tileRenderer"] as? [String: Any],
                          let thr = (tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any],
                          thr["thumbnailOverlays"] != nil  // absent on deleted/unavailable videos
                    else { return nil }
                    return InnertubeClient.parseTileRenderer(tile)
                }
                print("[Innertube] playlist \(playlistId): \(videos.count) videos via Innertube")
                if videos.isEmpty {
                    completion(.failure(APIError.decodingFailed))
                } else {
                    completion(.success(videos))
                }
            }
        }
    }

    func sendVote(endpoint: String, videoId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let e):
                print("[Innertube] sendVote '\(endpoint)' token error: \(e)")
                completion(.failure(e))
            case .success(let token):
                guard let url = URL(string: "\(self.baseURL)/\(endpoint)") else {
                    completion(.failure(APIError.invalidURL)); return
                }
                // Must use TV client context — token was issued for TVHTML5
                var body = self.tvContext
                body["target"] = ["videoId": videoId]
                guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let headers: [String: String] = [
                    "Content-Type": "application/json",
                    "Authorization": "Bearer \(token)",
                    "X-Youtube-Client-Name": "7",
                    "X-Youtube-Client-Version": "7.20260311.12.00",
                ]
                print("[Innertube] sendVote '\(endpoint)' videoId=\(videoId)")
                self.api.post(url: url, headers: headers, body: bodyData) { result in
                    switch result {
                    case .failure(let e):
                        print("[Innertube] sendVote '\(endpoint)' failed: \(e)")
                        completion(.failure(e))
                    case .success(let data):
                        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "?"
                        print("[Innertube] sendVote '\(endpoint)' success, response: \(preview)")
                        completion(.success(()))
                    }
                }
            }
        }
    }


    // MARK: - Authenticated browse

    func authenticatedBrowse(browseId: String, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeBrowse(browseId: browseId, continuation: nil,
                                                          token: token, completion: completion)
            }
        }
    }

    /// Web-client authenticated browse — used for endpoints like FEhistory that return
    /// twoColumnBrowseResultsRenderer instead of the TV tvBrowseRenderer structure.
    func executeWebBrowse(browseId: String?, continuation: String?, token: String,
                                   completion: @escaping (Result<FeedPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = webContext
        if let c = continuation {
            body["continuation"] = c
        } else if let b = browseId {
            body["browseId"] = b
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token)",
            "X-Youtube-Client-Name": "1",
            "X-Youtube-Client-Version": "2.20260206.01.00",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36,gzip(gfe)",
            "Origin": "https://www.youtube.com",
            "Referer": "https://www.youtube.com/"
        ]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let page = InnertubeClient.parseWebBrowsePage(json)
                if page.videos.isEmpty {
                    let topKeys = json.keys.joined(separator: ", ")
                    let contentsKeys = (json["contents"] as? [String: Any])?.keys.joined(separator: ", ") ?? "nil"
                    print("[Innertube] web browse '\(browseId ?? "continuation")': 0 videos. topKeys=[\(topKeys)] contentsKeys=[\(contentsKeys)]")
                } else {
                    print("[Innertube] web browse '\(browseId ?? "continuation")': \(page.videos.count) videos")
                }
                completion(.success(page))
            }
        }
    }

    /// TV-client authenticated browse for FEhistory.
    /// TV context accepts Bearer token. Logs the raw structure on first call so we can
    /// determine the correct parse path.
    func executeTVHistoryBrowse(token: String, continuation: String?,
                                         completion: @escaping (Result<FeedPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        if let c = continuation {
            body["continuation"] = c
        } else {
            body["browseId"] = "FEhistory"
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                // Dump full JSON to ~/Documents/history_response.json for inspection
                if let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                    let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    if let file = docsDir?.appendingPathComponent("history_response.json") {
                        try? pretty.write(to: file)
                        print("[Innertube] TV history JSON dumped to: \(file.path)")
                    }
                    // Also log top-level and contents keys
                    let topKeys = json.keys.sorted().joined(separator: ", ")
                    let contentsKeys = (json["contents"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "nil (array or missing)"
                    print("[Innertube] TVhistory topKeys=[\(topKeys)] contentsKeys=[\(contentsKeys)]")
                }
                let page = InnertubeClient.parseTVHistoryPage(json)
                print("[Innertube] TV history: \(page.videos.count) videos, cont=\(page.continuation != nil)")
                completion(.success(page))
            }
        }
    }


    func executeBrowseAnonymous(browseId: String, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        // Use TV context without auth — same format as authenticated browse,
        // but TVHTML5 client works for public content without an OAuth token.
        var body = tvContext
        body["browseId"] = browseId
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        api.post(url: url, headers: ["Content-Type": "application/json"], body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let page = InnertubeClient.parsePageJSON(json)
                if page.videos.isEmpty {
                    print("[Innertube] executeBrowseAnonymous: empty result for browseId=\(browseId)")
                    completion(.failure(APIError.decodingFailed))
                } else {
                    completion(.success(page))
                }
            }
        }
    }

    func executeBrowse(browseId: String?, continuation: String?, token: String,
                                completion: @escaping (Result<FeedPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        if let c = continuation {
            body["continuation"] = c
        } else if let b = browseId {
            body["browseId"] = b
        }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let page = InnertubeClient.parsePageJSON(json)
                if page.videos.isEmpty {
                    completion(.failure(APIError.decodingFailed))
                } else {
                    completion(.success(page))
                }
            }
        }
    }

    func executeChannelBrowse(channelId: String, token: String,
                                      completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
        //print("[Innertube] channel browse TV attempt: \(channelId)")
        executeChannelBrowse(channelId: channelId, token: token, context: tvContext, completion: completion)
    }

    func executeChannelBrowse(channelId: String, token: String, context: [String: Any],
                                      completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var body = context
        body["browseId"] = channelId

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let error):
                let clientName = (((context["context"] as? [String: Any])?["client"] as? [String: Any])?["clientName"] as? String) ?? "unknown"
                print("[Innertube] channel browse request failed (\(clientName)) \(channelId): \(error)")
                completion(.failure(error))
            case .success(let data):
                let clientName = (((context["context"] as? [String: Any])?["client"] as? [String: Any])?["clientName"] as? String) ?? "unknown"
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let info = InnertubeClient.parseChannelInfo(json, fallbackChannelId: channelId)
                else {
                    print("[Innertube] channel browse parse failed (\(clientName)) for \(channelId)")
                    completion(.failure(APIError.decodingFailed))
                    return
                }
                //print("[Innertube] parsed channel info (\(clientName)) \(channelId), avatar: \(info.avatarURL ?? "nil"), title: \(info.title)")
                completion(.success(info))
            }
        }
    }

    func executeChannelPageBrowse(channelId: String, token: String,
                                          completion: @escaping (Result<ChannelPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        // TV request: subscribe state + video feed (requires Bearer auth)
        var tvBody = tvContext
        tvBody["browseId"] = channelId
        guard let tvBodyData = try? JSONSerialization.data(withJSONObject: tvBody) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        // WEB request: banner, verified, subscribers, description (fires in parallel, non-blocking)
        var webBody = webContext
        webBody["browseId"] = channelId
        let webBodyData = try? JSONSerialization.data(withJSONObject: webBody)

        // Protected by lock so TV callback can safely read webResult
        let lock = NSLock()
        var webResult: Result<Data, Error>?
        var webDone = false

        if let webData = webBodyData {
            api.post(url: url, headers: ["Content-Type": "application/json"], body: webData) { result in
                lock.lock()
                webResult = result
                webDone = true
                lock.unlock()
            }
        }

        let tvHeaders = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: tvHeaders, body: tvBodyData) { result in
            // Complete immediately when TV finishes — don't wait for web
            guard case .success(let tvData) = result,
                  let tvJson = try? JSONSerialization.jsonObject(with: tvData) as? [String: Any],
                  let tvInfo = InnertubeClient.parseChannelInfo(tvJson, fallbackChannelId: channelId)
            else {
                print("[Innertube] channel page parse failed for \(channelId)")
                if case .failure(let err) = result {
                    completion(.failure(err))
                } else {
                    completion(.failure(APIError.decodingFailed))
                }
                return
            }

            let page = InnertubeClient.parsePageJSON(tvJson)
            let subscribeState = InnertubeClient.parseSubscribeState(tvJson)

            // Use web data only if it already finished (non-blocking check)
            lock.lock()
            let webSnapshot = webDone ? webResult : nil
            lock.unlock()

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

            print("[Channel] parsed: title='\(finalInfo.title)' subs='\(finalInfo.subscriberCountText ?? "nil")' banner=\(finalInfo.bannerURL != nil ? "YES" : "NO") verified=\(finalInfo.isVerified)")
            completion(.success(ChannelPage(info: finalInfo,
                                            videosPage: page,
                                            subscribeButtonText: subscribeState.text,
                                            isSubscribed: subscribeState.isSubscribed)))
        }
    }

    func executeWatchNext(video: Video, token: String,
                                  anonymous: Bool = false,
                                  cancellationToken: CancellationToken? = nil,
                                  completion: @escaping (Result<WatchPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/next") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var body = anonymous ? webContext : tvContext
        body["videoId"] = video.id

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        var headers: [String: String] = ["Content-Type": "application/json"]
        if !anonymous && !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        api.post(url: url, headers: headers, body: bodyData, cancellationToken: cancellationToken) { result in
            switch result {
            case .failure(let error):
                print("[Innertube] watch next request failed \(video.id): \(error)")
                completion(.failure(error))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let page = InnertubeClient.parseWatchPage(json, fallbackVideo: video)
                else {
                    print("[Innertube] watch next parse failed for \(video.id)")
                    completion(.failure(APIError.decodingFailed))
                    return
                }
                completion(.success(page))
            }
        }
    }

    func executeComments(videoId: String, continuation: String?,
                                 cancellationToken: CancellationToken? = nil,
                                 completion: @escaping (Result<CommentsPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/next") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var body = webContext
        if let continuation {
            body["continuation"] = continuation
        } else {
            body["continuation"] = Self.buildCommentsContinuation(videoId: videoId, sortBy: 0, commentId: nil)
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        let headers = [
            "Content-Type": "application/json",
            "X-Youtube-Client-Name": DirectPlaybackClient.web.clientHeaderName,
            "X-Youtube-Client-Version": DirectPlaybackClient.web.clientVersion
        ]

        api.post(url: url, headers: headers, body: bodyData, cancellationToken: cancellationToken) { result in
            switch result {
            case .failure(let error):
                print("[Innertube] comments request failed \(videoId): \(error)")
                completion(.failure(error))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let page = Self.parseCommentsPage(json)
                else {
                    print("[Innertube] comments parse failed for \(videoId)")
                    completion(.failure(APIError.decodingFailed))
                    return
                }
                completion(.success(page))
            }
        }
    }

    func executePlayerDebug(videoId: String, token: String,
                                    completion: @escaping (Result<Void, Error>) -> Void) {
        let contexts: [(name: String, body: [String: Any], auth: Bool)] = [
            ("TVHTML5", tvContext, true),
            ("WEB", webContext, false)
        ]

        let group = DispatchGroup()
        var firstError: Error?

        for context in contexts {
            group.enter()
            executePlayer(videoId: videoId, contextName: context.name, context: context.body, token: context.auth ? token : nil) { result in
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(()))
            }
        }
    }

    func executeDirectPlayback(videoId: String, client: DirectPlaybackClient, token: String, poToken: String?,
                                       visitorData: String? = nil,
                                       cancellationToken: CancellationToken? = nil,
                                       completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        let urlStr = "\(baseURL)/player\(client.playerURLSuffix)"
        guard let url = URL(string: urlStr) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var body = client.context
        body["videoId"] = videoId
        if client.requiresContentCheckFlags {
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
            body["playbackContext"] = [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        }
        if let poToken, !poToken.isEmpty {
            body["serviceIntegrityDimensions"] = [
                "poToken": poToken
            ]
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        let requestHeaders = client.apiHeaders(token: token, visitorData: visitorData)

        print("[Innertube] sending \(client) request to \(url.absoluteString), bodySize=\(bodyData.count), headers=\(requestHeaders.keys.sorted().joined(separator: ","))")

        api.post(url: url, headers: requestHeaders, body: bodyData, cancellationToken: cancellationToken) { result in
            switch result {
            case .failure(let error):
                print("[Innertube] direct playback request failed \(videoId), client: \(client): \(error)")
                completion(.failure(error))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let info = Self.parseDirectPlaybackInfo(json)
                else {
                    print("[Innertube] direct playback parse failed \(videoId), client: \(client), responseBytes=\(data.count)")
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("[Innertube] response topKeys (\(client)): \(json.keys.sorted().joined(separator: ", "))")
                        if let errorObj = json["error"] {
                            if let errorData = try? JSONSerialization.data(withJSONObject: errorObj, options: .prettyPrinted),
                               let errorStr = String(data: errorData, encoding: .utf8) {
                                print("[Innertube] error body (\(client)): \(errorStr)")
                            }
                        }
                        Self.logPlayerDebug(videoId: videoId, contextName: client.description, json: json)
                    } else {
                        let preview = String(data: data.prefix(500), encoding: .utf8) ?? "binary"
                        print("[Innertube] response not JSON (\(client)): \(preview)")
                    }
                    completion(.failure(APIError.decodingFailed))
                    return
                }

                let progressive = info.progressiveURL?.absoluteString ?? "nil"
                let video = info.videoURL?.absoluteString ?? "nil"
                let audio = info.audioURL?.absoluteString ?? "nil"
                let sabr = info.serverAbrStreamingURL?.absoluteString ?? "nil"
                let videoUstreamerLength = info.videoPlaybackUstreamerConfig?.count ?? 0
                let onesieUstreamerLength = info.onesieUstreamerConfig?.count ?? 0
                print("[Innertube] direct playback selected \(videoId), client: \(client): progressive=\(progressive), video=\(video), audio=\(audio), sabr=\(sabr), ustreamer=\(info.hasVideoPlaybackUstreamerConfig), videoUstreamerLen=\(videoUstreamerLength), onesieUstreamerLen=\(onesieUstreamerLength)")
                completion(.success(info))
            }
        }
    }

    func executePlayer(videoId: String, contextName: String, context: [String: Any], token: String?,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/player") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var body = context
        body["videoId"] = videoId

        if contextName != "TVHTML5" {
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
        }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        var headers: [String: String] = [
            "Content-Type": "application/json"
        ]

        if contextName == "WEB" {
            headers["X-Youtube-Client-Name"] = DirectPlaybackClient.web.clientHeaderName
            headers["X-Youtube-Client-Version"] = DirectPlaybackClient.web.clientVersion
        }

        if let token {
            headers["Authorization"] = "Bearer \(token)"
        }

        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let error):
                print("[Innertube] player debug request failed (\(contextName)) \(videoId): \(error)")
                completion(.failure(error))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("[Innertube] player debug decode failed (\(contextName)) \(videoId)")
                    completion(.failure(APIError.decodingFailed))
                    return
                }

                Self.logPlayerDebug(videoId: videoId, contextName: contextName, json: json)
                completion(.success(()))
            }
        }
    }

    func executeSubscribe(channelId: String, token: String, cancellationToken: CancellationToken? = nil,
                          completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/subscription/subscribe") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        body["channelIds"] = [channelId]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token)",
        ]
        print("[Innertube] executeSubscribe channelId=\(channelId)")
        let task = api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e):
                print("[Innertube] executeSubscribe failed: \(e)")
                completion(.failure(e))
            case .success(let data):
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? "?"
                print("[Innertube] executeSubscribe success, response: \(preview)")
                completion(.success(()))
            }
        }
        cancellationToken?.register(task)
    }

    func executeUnsubscribe(channelId: String, token: String, cancellationToken: CancellationToken? = nil,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/subscription/unsubscribe") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = tvContext
        body["channelIds"] = [channelId]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers: [String: String] = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token)",
        ]
        print("[Innertube] executeUnsubscribe channelId=\(channelId)")
        let task = api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e):
                print("[Innertube] executeUnsubscribe failed: \(e)")
                completion(.failure(e))
            case .success(let data):
                let preview = String(data: data.prefix(200), encoding: .utf8) ?? "?"
                print("[Innertube] executeUnsubscribe success, response: \(preview)")
                completion(.success(()))
            }
        }
        cancellationToken?.register(task)
    }

    // Fetch first video thumbnail for a playlist (used to show cover in playlist list)
    private func fetchPlaylistFirstThumbnail(playlistId: String, token: String,
                                              completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else { completion(nil); return }
        var body = tvContext
        body["browseId"] = "VL\(playlistId)"
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil); return
        }
        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            guard case .success(let data) = result,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(nil); return }
            let right = ((json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any])
                .flatMap { $0["content"] as? [String: Any] }
                .flatMap { $0["tvSurfaceContentRenderer"] as? [String: Any] }
                .flatMap { $0["content"] as? [String: Any] }
                .flatMap { $0["twoColumnRenderer"] as? [String: Any] }
                .flatMap { $0["rightColumn"] as? [String: Any] }
            let items = (right?["playlistVideoListRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
            let best: String? = items?.lazy.compactMap { item -> String? in
                guard let tile = item["tileRenderer"] as? [String: Any],
                      let thr = (tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any],
                      thr["thumbnailOverlays"] != nil  // absent on deleted/unavailable videos
                else { return nil }
                let thumbs = (thr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
                return thumbs?.last.flatMap { $0["url"] as? String }
                    ?? thumbs?.first.flatMap { $0["url"] as? String }
            }.first
            completion(best)
        }
    }

}
