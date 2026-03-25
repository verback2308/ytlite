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
        guard let url = URL(string:
            "https://www.googleapis.com/youtube/v3/playlists?part=snippet,contentDetails&mine=true&maxResults=50")
        else { completion(.failure(APIError.invalidURL)); return }
        let headers = ["Authorization": "Bearer \(token)"]
        api.get(url: url, headers: headers) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]]
                else { completion(.failure(APIError.decodingFailed)); return }
                let playlists: [Playlist] = items.compactMap { item in
                    guard let id = item["id"] as? String,
                          let snippet = item["snippet"] as? [String: Any],
                          let title = snippet["title"] as? String
                    else { return nil }
                    let desc = snippet["description"] as? String ?? ""
                    let thumbs = snippet["thumbnails"] as? [String: Any] ?? [:]
                    let thumb = (thumbs["medium"] ?? thumbs["default"]) as? [String: Any]
                    let thumbURL = thumb?["url"] as? String
                    let count = (item["contentDetails"] as? [String: Any])?["itemCount"] as? Int
                    return Playlist(id: id, title: title, description: desc,
                                    thumbnailURL: thumbURL, itemCount: count)
                }
                completion(.success(playlists))
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
        var body = webContext
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

        var body = tvContext
        body["browseId"] = channelId

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let error):
                print("[Innertube] channel page request failed \(channelId): \(error)")
                completion(.failure(error))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let info = InnertubeClient.parseChannelInfo(json, fallbackChannelId: channelId)
                else {
                    print("[Innertube] channel page parse failed for \(channelId)")
                    completion(.failure(APIError.decodingFailed))
                    return
                }

                let page = InnertubeClient.parsePageJSON(json)
                let subscribeState = InnertubeClient.parseSubscribeState(json)
                completion(.success(ChannelPage(info: info,
                                                videosPage: page,
                                                subscribeButtonText: subscribeState.text,
                                                isSubscribed: subscribeState.isSubscribed)))
            }
        }
    }

    func executeWatchNext(video: Video, token: String,
                                  completion: @escaping (Result<WatchPage, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/next") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var body = tvContext
        body["videoId"] = video.id

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed))
            return
        }

        let headers = ["Content-Type": "application/json", "Authorization": "Bearer \(token)"]
        api.post(url: url, headers: headers, body: bodyData) { result in
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

        api.post(url: url, headers: headers, body: bodyData) { result in
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
            ("WEB", webContext, false),
            ("ANDROID", androidContext, false)
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
                                       completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        let urlStr: String
        switch client {
        case .ios:
            urlStr = "\(baseURL)/player?prettyPrint=false&key=AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc"
        default:
            urlStr = client.usesCookieAuth ? "\(baseURL)/player?prettyPrint=false" : "\(baseURL)/player"
        }
        guard let url = URL(string: urlStr) else {
            completion(.failure(APIError.invalidURL))
            return
        }

        let context: [String: Any]
        switch client {
        case .tvHTML5:
            context = tvContext
        case .web:
            context = webContext
        case .android:
            context = androidContext
        case .androidVR:
            context = androidVRContext
        case .ios:
            context = iosContext
        }

        var body = context
        body["videoId"] = videoId
        switch client {
        case .tvHTML5:
            break
        case .web, .android, .androidVR, .ios:
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

        var requestHeaders: [String: String] = [
            "Content-Type": "application/json"
        ]
        if !client.usesCookieAuth {
            requestHeaders["Authorization"] = "Bearer \(token)"
        }
        switch client {
        case .tvHTML5:
            break
        case .web:
            requestHeaders["X-Youtube-Client-Name"] = DirectPlaybackClient.web.clientHeaderName
            requestHeaders["X-Youtube-Client-Version"] = DirectPlaybackClient.web.clientVersion
        case .android:
            requestHeaders["X-Youtube-Client-Name"] = DirectPlaybackClient.android.clientHeaderName
            requestHeaders["X-Youtube-Client-Version"] = DirectPlaybackClient.android.clientVersion
        case .androidVR:
            requestHeaders["X-YouTube-Client-Name"] = DirectPlaybackClient.androidVR.clientHeaderName
            requestHeaders["X-YouTube-Client-Version"] = DirectPlaybackClient.androidVR.clientVersion
            requestHeaders["User-Agent"] = "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
            requestHeaders["Origin"] = "https://www.youtube.com"
            if let visitorData = visitorData, !visitorData.isEmpty {
                requestHeaders["X-Goog-Visitor-Id"] = visitorData
            }
        case .ios:
            requestHeaders["X-YouTube-Client-Name"] = DirectPlaybackClient.ios.clientHeaderName
            requestHeaders["X-YouTube-Client-Version"] = DirectPlaybackClient.ios.clientVersion
            requestHeaders["User-Agent"] = "com.google.ios.youtube/19.45.4 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X;)"
            requestHeaders["Origin"] = "https://www.youtube.com"
            if let visitorData = visitorData, !visitorData.isEmpty {
                requestHeaders["X-Goog-Visitor-Id"] = visitorData
            }
        }

        print("[Innertube] sending \(client) request to \(url.absoluteString), bodySize=\(bodyData.count), headers=\(requestHeaders.keys.sorted().joined(separator: ","))")

        api.post(url: url, headers: requestHeaders, body: bodyData) { result in
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
        } else if contextName == "ANDROID" {
            headers["X-Youtube-Client-Name"] = "3"
            headers["X-Youtube-Client-Version"] = androidClientVersion
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

}
