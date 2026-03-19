import Foundation

enum DirectPlaybackClient: Equatable, CustomStringConvertible {
    case tvHTML5
    case web
    case android

    var clientName: String {
        switch self {
        case .tvHTML5:
            return "TVHTML5"
        case .web:
            return "WEB"
        case .android:
            return "ANDROID"
        }
    }

    var clientVersion: String {
        switch self {
        case .tvHTML5:
            return "7.20230405.08.01"
        case .web:
            return "2.20231121.08.00"
        case .android:
            return "19.09.37"
        }
    }

    var clientHeaderName: String {
        switch self {
        case .tvHTML5:
            return "7"
        case .web:
            return "1"
        case .android:
            return "3"
        }
    }

    var description: String {
        clientName
    }
}

final class InnertubeClient: VideoService {

    private let api = APIClient()
    private let baseURL = "https://www.youtube.com/youtubei/v1"
    private let androidClientVersion = "19.09.37"

    private let webContext: [String: Any] = [
        "context": ["client": ["clientName": DirectPlaybackClient.web.clientName, "clientVersion": DirectPlaybackClient.web.clientVersion, "hl": "en", "gl": "US"]]
    ]
    private let androidContext: [String: Any] = [
        "context": ["client": ["clientName": DirectPlaybackClient.android.clientName, "clientVersion": DirectPlaybackClient.android.clientVersion, "hl": "en", "gl": "US", "androidSdkVersion": 28]]
    ]
    private let tvContext: [String: Any] = [
        "context": ["client": ["clientName": DirectPlaybackClient.tvHTML5.clientName, "clientVersion": DirectPlaybackClient.tvHTML5.clientVersion, "hl": "en", "gl": "US"]]
    ]

    // MARK: - VideoService

    func fetchHomeFeed(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        authenticatedBrowse(browseId: "FEwhat_to_watch", completion: completion)
    }

    func fetchSubscriptionFeed(completion: @escaping (Result<FeedPage, Error>) -> Void) {
        authenticatedBrowse(browseId: "FEsubscriptions", completion: completion)
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
        print("[Innertube] fetchChannelInfo start: \(channelId)")
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

    func fetchWatchPage(video: Video, completion: @escaping (Result<WatchPage, Error>) -> Void) {
        print("[Innertube] fetchWatchPage start: \(video.id)")
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                print("[Innertube] fetchWatchPage token failure for \(video.id): \(error)")
                completion(.failure(error))
            case .success(let token):
                self?.executeWatchNext(video: video, token: token, completion: completion)
            }
        }
    }

    func fetchComments(videoId: String, continuation: String? = nil,
                       completion: @escaping (Result<CommentsPage, Error>) -> Void) {
        print("[Innertube] fetchComments start: \(videoId), continuation: \(continuation != nil)")
        executeComments(videoId: videoId, continuation: continuation, completion: completion)
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

    func fetchDirectPlayback(videoId: String, client: DirectPlaybackClient = .tvHTML5, poToken: String? = nil,
                             completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        print("[Innertube] fetchDirectPlayback start: \(videoId), client: \(client)")
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeDirectPlayback(videoId: videoId, client: client, token: token, poToken: poToken, completion: completion)
            }
        }
    }

    // MARK: - Authenticated browse

    private func authenticatedBrowse(browseId: String, completion: @escaping (Result<FeedPage, Error>) -> Void) {
        OAuthClient.shared.validToken { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let token): self?.executeBrowse(browseId: browseId, continuation: nil,
                                                          token: token, completion: completion)
            }
        }
    }

    private func executeBrowse(browseId: String?, continuation: String?, token: String,
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

    private func executeChannelBrowse(channelId: String, token: String,
                                      completion: @escaping (Result<ChannelInfo, Error>) -> Void) {
        print("[Innertube] channel browse TV attempt: \(channelId)")
        executeChannelBrowse(channelId: channelId, token: token, context: tvContext, completion: completion)
    }

    private func executeChannelBrowse(channelId: String, token: String, context: [String: Any],
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
                print("[Innertube] parsed channel info (\(clientName)) \(channelId), avatar: \(info.avatarURL ?? "nil"), title: \(info.title)")
                completion(.success(info))
            }
        }
    }

    private func executeChannelPageBrowse(channelId: String, token: String,
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

    private func executeWatchNext(video: Video, token: String,
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

    private func executeComments(videoId: String, continuation: String?,
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

    private func executePlayerDebug(videoId: String, token: String,
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

    private func executeDirectPlayback(videoId: String, client: DirectPlaybackClient, token: String, poToken: String?,
                                       completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/player") else {
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
        }

        var body = context
        body["videoId"] = videoId
        switch client {
        case .tvHTML5:
            break
        case .web, .android:
            body["contentCheckOk"] = true
            body["racyCheckOk"] = true
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

        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(token)"
        ]
        var requestHeaders = headers
        switch client {
        case .tvHTML5:
            break
        case .web:
            requestHeaders["X-Youtube-Client-Name"] = DirectPlaybackClient.web.clientHeaderName
            requestHeaders["X-Youtube-Client-Version"] = DirectPlaybackClient.web.clientVersion
        case .android:
            requestHeaders["X-Youtube-Client-Name"] = DirectPlaybackClient.android.clientHeaderName
            requestHeaders["X-Youtube-Client-Version"] = DirectPlaybackClient.android.clientVersion
        }

        api.post(url: url, headers: requestHeaders, body: bodyData) { result in
            switch result {
            case .failure(let error):
                print("[Innertube] direct playback request failed \(videoId), client: \(client): \(error)")
                completion(.failure(error))
            case .success(let data):
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let info = Self.parseDirectPlaybackInfo(json)
                else {
                    print("[Innertube] direct playback parse failed \(videoId), client: \(client)")
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Self.logPlayerDebug(videoId: videoId, contextName: client.description, json: json)
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

    private func executePlayer(videoId: String, contextName: String, context: [String: Any], token: String?,
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

    // MARK: - JSON parsing

    private static func parseWatchPage(_ json: [String: Any], fallbackVideo: Video) -> WatchPage? {
        let metadata = parseWatchMetadata(json)
        let channelInfo = parseWatchChannelInfo(json, fallbackVideo: fallbackVideo)
        let subscribeState = parseSubscribeState(json)
        let description = parseWatchDescription(json)

        let resolvedVideo = Video(
            id: fallbackVideo.id,
            title: metadata.title ?? fallbackVideo.title,
            channelId: channelInfo?.id ?? fallbackVideo.channelId,
            channelName: channelInfo?.title.isEmpty == false ? channelInfo!.title : fallbackVideo.channelName,
            channelAvatarURL: channelInfo?.avatarURL ?? fallbackVideo.channelAvatarURL,
            thumbnailURL: fallbackVideo.thumbnailURL,
            viewCount: metadata.viewCountText ?? fallbackVideo.viewCount,
            publishedAt: metadata.publishedText ?? fallbackVideo.publishedAt,
            duration: fallbackVideo.duration
        )

        let relatedVideos = collectTileRenderers(in: json)
            .compactMap(parseTileRenderer)
            .filter { $0.id != fallbackVideo.id }
            .reduce(into: [Video]()) { partialResult, video in
                if partialResult.contains(where: { $0.id == video.id }) { return }
                partialResult.append(video)
            }

        return WatchPage(video: resolvedVideo,
                         description: description,
                         channelInfo: channelInfo,
                         subscribeButtonText: subscribeState.text,
                         isSubscribed: subscribeState.isSubscribed,
                         relatedVideos: relatedVideos)
    }

    private static func parseCommentsPage(_ json: [String: Any]) -> CommentsPage? {
        let mutations = ((((json["frameworkUpdates"] as? [String: Any])?["entityBatchUpdate"] as? [String: Any])?["mutations"]) as? [[String: Any]]) ?? []
        let threads = collectCommentThreads(in: json)
        let comments = threads.compactMap { parseComment(from: $0, mutations: mutations) }
        let continuation = findCommentsContinuation(in: json)
        let title = findCommentsTitle(in: json)

        guard !comments.isEmpty || continuation != nil else { return nil }
        return CommentsPage(title: title, comments: comments, continuation: continuation)
    }

    static func parsePlayerJSON(_ json: [String: Any]) -> DirectPlaybackInfo? {
        let topKeys = json.keys.sorted().joined(separator: ", ")
        print("[InnertubeClient] parsePlayerJSON topKeys: \(topKeys)")
        if let sd = json["streamingData"] as? [String: Any] {
            let formats = (sd["formats"] as? [[String: Any]])?.count ?? 0
            let adaptive = (sd["adaptiveFormats"] as? [[String: Any]])?.count ?? 0
            print("[InnertubeClient] streamingData found: formats=\(formats) adaptive=\(adaptive)")
        } else {
            print("[InnertubeClient] streamingData MISSING — playabilityStatus: \((json["playabilityStatus"] as? [String: Any])?["status"] ?? "nil")")
        }
        return parseDirectPlaybackInfo(json)
    }

    private static func parseDirectPlaybackInfo(_ json: [String: Any]) -> DirectPlaybackInfo? {
        guard let streamingData = json["streamingData"] as? [String: Any] else { return nil }

        let formats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []

        func directURL(_ format: [String: Any]) -> URL? {
            guard let value = format["url"] as? String, !value.isEmpty else { return nil }
            return URL(string: value)
        }

        func mimeType(_ format: [String: Any]) -> String {
            format["mimeType"] as? String ?? ""
        }

        func height(_ format: [String: Any]) -> Int {
            format["height"] as? Int ?? 0
        }

        func bitrate(_ format: [String: Any]) -> Int {
            format["bitrate"] as? Int ?? 0
        }

        func itag(_ format: [String: Any]) -> Int? {
            format["itag"] as? Int
        }

        func sabrFormatInfo(_ format: [String: Any]) -> SabrFormatInfo? {
            guard let formatItag = itag(format) else { return nil }
            let audioTrack = format["audioTrack"] as? [String: Any]
            return SabrFormatInfo(
                itag: formatItag,
                lastModified: (format["lastModified"] as? String) ?? (format["lmt"] as? String),
                xtags: format["xtags"] as? String,
                audioTrackId: audioTrack?["id"] as? String,
                isDrc: (format["isDrc"] as? Bool) ?? ((format["xtags"] as? String)?.contains("drc=1") == true),
                mimeType: format["mimeType"] as? String,
                bitrate: format["bitrate"] as? Int,
                width: format["width"] as? Int,
                height: format["height"] as? Int
            )
        }

        let progressive = formats
            .filter { directURL($0) != nil && mimeType($0).contains("video/mp4") }
            .sorted { bitrate($0) > bitrate($1) }
            .first

        let video = adaptiveFormats
            .filter {
                directURL($0) != nil &&
                mimeType($0).contains("video/mp4") &&
                mimeType($0).contains("avc1") &&
                height($0) > 0 &&
                height($0) <= 720
            }
            .sorted { lhs, rhs in
                let lhsHeight = height(lhs)
                let rhsHeight = height(rhs)
                if lhsHeight == rhsHeight {
                    return bitrate(lhs) > bitrate(rhs)
                }
                return lhsHeight > rhsHeight
            }
            .first

        let audio = adaptiveFormats
            .filter { directURL($0) != nil && mimeType($0).contains("audio/mp4") }
            .sorted { bitrate($0) > bitrate($1) }
            .first

        let hlsManifestURL = (streamingData["hlsManifestUrl"] as? String).flatMap(URL.init(string:))
        let dashManifestURL = (streamingData["dashManifestUrl"] as? String).flatMap(URL.init(string:))
        let progressiveURL = progressive.flatMap(directURL)
        let videoURL = video.flatMap(directURL)
        let audioURL = audio.flatMap(directURL)
        let serverAbrStreamingURL = (streamingData["serverAbrStreamingUrl"] as? String).flatMap(URL.init(string:))
        let mediaCommonConfig = (json["playerConfig"] as? [String: Any])?["mediaCommonConfig"] as? [String: Any]
        let mediaUstreamerRequestConfig = mediaCommonConfig?["mediaUstreamerRequestConfig"] as? [String: Any]
        let videoPlaybackUstreamerConfig = mediaUstreamerRequestConfig?["videoPlaybackUstreamerConfig"] as? String
        let onesieUstreamerConfig = mediaUstreamerRequestConfig?["onesieUstreamerConfig"] as? String
        let hasVideoPlaybackUstreamerConfig = videoPlaybackUstreamerConfig?.isEmpty == false

        guard hlsManifestURL != nil || dashManifestURL != nil || progressiveURL != nil || (videoURL != nil && audioURL != nil) || serverAbrStreamingURL != nil else {
            return nil
        }

        return DirectPlaybackInfo(
            hlsManifestURL: hlsManifestURL,
            dashManifestURL: dashManifestURL,
            progressiveURL: progressiveURL,
            videoURL: videoURL,
            audioURL: audioURL,
            serverAbrStreamingURL: serverAbrStreamingURL,
            videoPlaybackUstreamerConfig: videoPlaybackUstreamerConfig,
            onesieUstreamerConfig: onesieUstreamerConfig,
            sabrVideoFormat: video.flatMap(sabrFormatInfo),
            sabrAudioFormat: audio.flatMap(sabrFormatInfo),
            videoItag: video.flatMap(itag) ?? progressive.flatMap(itag),
            audioItag: audio.flatMap(itag),
            qualityLabel: (video?["qualityLabel"] as? String) ?? (progressive?["qualityLabel"] as? String),
            visitorData: ((json["responseContext"] as? [String: Any])?["visitorData"] as? String),
            hasVideoPlaybackUstreamerConfig: hasVideoPlaybackUstreamerConfig
        )
    }

    private static func logPlayerDebug(videoId: String, contextName: String, json: [String: Any]) {
        let playability = json["playabilityStatus"] as? [String: Any]
        let status = playability?["status"] as? String ?? "nil"
        let reason = playability?["reason"] as? String ?? "nil"
        let streamingData = json["streamingData"] as? [String: Any]
        let formats = streamingData?["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData?["adaptiveFormats"] as? [[String: Any]] ?? []
        let hlsManifestURL = streamingData?["hlsManifestUrl"] as? String ?? "nil"
        let dashManifestURL = streamingData?["dashManifestUrl"] as? String ?? "nil"
        let sabrURL = streamingData?["serverAbrStreamingUrl"] as? String ?? "nil"

        func summarize(_ format: [String: Any]) -> String {
            let itag = format["itag"] as? Int ?? -1
            let mimeType = format["mimeType"] as? String ?? "nil"
            let hasURL = (format["url"] as? String)?.isEmpty == false
            let hasCipher = (format["signatureCipher"] as? String)?.isEmpty == false || (format["cipher"] as? String)?.isEmpty == false
            let quality = (format["qualityLabel"] as? String) ?? (format["audioQuality"] as? String) ?? "nil"
            return "itag=\(itag), quality=\(quality), mime=\(mimeType), url=\(hasURL), cipher=\(hasCipher)"
        }

        let formatSummary = formats.prefix(3).map(summarize).joined(separator: " | ")
        let adaptiveSummary = adaptiveFormats.prefix(5).map(summarize).joined(separator: " | ")

        print("[Innertube] player debug (\(contextName)) \(videoId): status=\(status), reason=\(reason)")
        print("[Innertube] player debug (\(contextName)) manifests: hls=\(hlsManifestURL), dash=\(dashManifestURL), sabr=\(sabrURL)")
        print("[Innertube] player debug (\(contextName)) formats=\(formats.count) [\(formatSummary)]")
        print("[Innertube] player debug (\(contextName)) adaptive=\(adaptiveFormats.count) [\(adaptiveSummary)]")

        if contextName == "TVHTML5" {
            logDirectPlaybackCandidates(videoId: videoId, formats: formats, adaptiveFormats: adaptiveFormats)
        }
    }

    private static func logDirectPlaybackCandidates(videoId: String, formats: [[String: Any]], adaptiveFormats: [[String: Any]]) {
        func stringValue(_ format: [String: Any], key: String) -> String {
            format[key] as? String ?? "nil"
        }

        func directURL(_ format: [String: Any]) -> String? {
            let url = format["url"] as? String
            return url?.isEmpty == false ? url : nil
        }

        func mimeType(_ format: [String: Any]) -> String {
            format["mimeType"] as? String ?? ""
        }

        func height(_ format: [String: Any]) -> Int {
            format["height"] as? Int ?? 0
        }

        func bitrate(_ format: [String: Any]) -> Int {
            format["bitrate"] as? Int ?? 0
        }

        func itag(_ format: [String: Any]) -> Int {
            format["itag"] as? Int ?? -1
        }

        let progressive = formats
            .filter { directURL($0) != nil }
            .sorted { bitrate($0) > bitrate($1) }

        let videoCandidates = adaptiveFormats
            .filter { directURL($0) != nil && mimeType($0).contains("video/mp4") && mimeType($0).contains("avc1") }
            .sorted { lhs, rhs in
                let lhsHeight = height(lhs)
                let rhsHeight = height(rhs)
                if lhsHeight == rhsHeight {
                    return bitrate(lhs) > bitrate(rhs)
                }
                return lhsHeight > rhsHeight
            }

        let audioCandidates = adaptiveFormats
            .filter { directURL($0) != nil && mimeType($0).contains("audio/mp4") }
            .sorted { bitrate($0) > bitrate($1) }

        if let bestProgressive = progressive.first, let url = directURL(bestProgressive) {
            let quality = stringValue(bestProgressive, key: "qualityLabel")
            print("[Innertube] player direct (\(videoId)) progressive: itag=\(itag(bestProgressive)), quality=\(quality), mime=\(mimeType(bestProgressive)), bitrate=\(bitrate(bestProgressive)), url=\(url)")
        } else {
            print("[Innertube] player direct (\(videoId)) progressive: none")
        }

        let topVideoSummary = videoCandidates.prefix(3).map {
            let quality = stringValue($0, key: "qualityLabel")
            return "itag=\(itag($0)), quality=\(quality), bitrate=\(bitrate($0)), mime=\(mimeType($0))"
        }.joined(separator: " | ")
        let topAudioSummary = audioCandidates.prefix(3).map {
            let audioQuality = stringValue($0, key: "audioQuality")
            return "itag=\(itag($0)), audio=\(audioQuality), bitrate=\(bitrate($0)), mime=\(mimeType($0))"
        }.joined(separator: " | ")

        print("[Innertube] player direct (\(videoId)) mp4 video candidates: \(videoCandidates.count) [\(topVideoSummary)]")
        print("[Innertube] player direct (\(videoId)) mp4 audio candidates: \(audioCandidates.count) [\(topAudioSummary)]")

        if let bestVideo = videoCandidates.first, let bestAudio = audioCandidates.first,
           let videoURL = directURL(bestVideo), let audioURL = directURL(bestAudio) {
            let videoQuality = stringValue(bestVideo, key: "qualityLabel")
            let audioQuality = stringValue(bestAudio, key: "audioQuality")
            print("[Innertube] player direct (\(videoId)) selected video: itag=\(itag(bestVideo)), quality=\(videoQuality), url=\(videoURL)")
            print("[Innertube] player direct (\(videoId)) selected audio: itag=\(itag(bestAudio)), quality=\(audioQuality), url=\(audioURL)")
        }
    }

    private static func parsePageJSON(_ json: [String: Any]) -> FeedPage {
        // Continuation response
        if let cc = json["continuationContents"] as? [String: Any],
           let slr = cc["sectionListContinuation"] as? [String: Any] {
            return parseSectionList(slr)
        }
        // Initial browse response
        if let slr = extractSectionList(from: json) {
            return parseSectionList(slr)
        }
        let contentsKeys = (json["contents"] as? [String: Any])?.keys.joined(separator: ", ") ?? "nil"
        print("[Innertube] parsePageJSON: unrecognized structure. contents keys: \(contentsKeys)")
        return FeedPage(videos: [], continuation: nil)
    }

    private static func extractSectionList(from json: [String: Any]) -> [String: Any]? {
        let tvBrowse = (json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any]
        let content = tvBrowse?["content"] as? [String: Any]

        // Home feed path
        if let tvSurface = content?["tvSurfaceContentRenderer"] as? [String: Any],
           let slr = (tvSurface["content"] as? [String: Any])?["sectionListRenderer"] as? [String: Any] {
            return slr
        }

        // Subscriptions path
        if let nav = content?["tvSecondaryNavRenderer"] as? [String: Any],
           let sections = nav["sections"] as? [[String: Any]],
           let tabs = (sections.first?["tvSecondaryNavSectionRenderer"] as? [String: Any])?["tabs"] as? [[String: Any]],
           let tabContent = (tabs.first?["tabRenderer"] as? [String: Any])?["content"] as? [String: Any],
           let tvSurface = tabContent["tvSurfaceContentRenderer"] as? [String: Any],
           let slr = (tvSurface["content"] as? [String: Any])?["sectionListRenderer"] as? [String: Any] {
            return slr
        }
        return nil
    }

    private static func parseSectionList(_ slr: [String: Any]) -> FeedPage {
        let sections = slr["contents"] as? [[String: Any]] ?? []
        var videos: [Video] = []

        for section in sections {
            guard let shelf = section["shelfRenderer"] as? [String: Any],
                  let shelfContent = shelf["content"] as? [String: Any],
                  let items = (shelfContent["horizontalListRenderer"] as? [String: Any])?["items"] as? [[String: Any]]
            else { continue }
            for item in items {
                if let tile = item["tileRenderer"] as? [String: Any],
                   let video = parseTileRenderer(tile) {
                    videos.append(video)
                }
            }
        }

        let continuation = (slr["continuations"] as? [[String: Any]])?
            .first.flatMap { ($0["nextContinuationData"] as? [String: Any])?["continuation"] as? String }

        return FeedPage(videos: videos, continuation: continuation)
    }

    private static func parseWatchMetadata(_ json: [String: Any]) -> (title: String?, viewCountText: String?, publishedText: String?) {
        if let renderer = firstRenderer(in: json, named: "slimVideoMetadataRenderer") {
            let title = simpleText(from: renderer["title"])
            let lines = renderer["lines"] as? [[String: Any]] ?? []
            var parts: [String] = []

            for line in lines {
                let items = (line["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
                for item in items {
                    if let text = simpleText(from: (item["lineItemRenderer"] as? [String: Any])?["text"]),
                       !text.isEmpty,
                       text != "•" {
                        parts.append(text)
                    }
                }
            }

            return (title, parts.first, parts.dropFirst().first)
        }

        if let renderer = firstRenderer(in: json, named: "videoMetadataRenderer") {
            let title = simpleText(from: renderer["title"])
            let viewCountText = simpleText(from: renderer["viewCountText"])
            let publishedText = simpleText(from: renderer["dateText"])
            return (title, viewCountText, publishedText)
        }

        return (nil, nil, nil)
    }

    private static func parseWatchDescription(_ json: [String: Any]) -> String? {
        if let renderer = firstRenderer(in: json, named: "expandableVideoDescriptionBodyRenderer") {
            return simpleText(from: renderer["descriptionBodyText"]) ?? simpleText(from: renderer["showMoreText"])
        }

        if let renderer = firstRenderer(in: json, named: "videoMetadataRenderer") {
            return simpleText(from: renderer["description"])
        }

        return nil
    }

    private static func parseWatchChannelInfo(_ json: [String: Any], fallbackVideo: Video) -> ChannelInfo? {
        if let lockup = firstRenderer(in: json, named: "avatarLockupRenderer") {
            let avatarURL = extractThumbnailURL(from: lockup["avatar"]) ??
                extractThumbnailURL(from: lockup["thumbnail"])
            let title = simpleText(from: lockup["title"]) ?? fallbackVideo.channelName
            let subtitle = simpleText(from: lockup["subtitle"])
            let channelId = firstMatchingBrowseId(in: lockup) ?? fallbackVideo.channelId ?? ""

            if !title.isEmpty || avatarURL != nil {
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subtitle)
            }
        }

        if let fallbackId = fallbackVideo.channelId {
            return ChannelInfo(id: fallbackId,
                               title: fallbackVideo.channelName,
                               avatarURL: fallbackVideo.channelAvatarURL,
                               subscriberCountText: nil)
        }

        return nil
    }

    private static func parseTileRenderer(_ tile: [String: Any]) -> Video? {
        guard let videoId = ((tile["onSelectCommand"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
        else { return nil }

        let meta = (tile["metadata"] as? [String: Any])?["tileMetadataRenderer"] as? [String: Any]
        let title = (meta?["title"] as? [String: Any])?["simpleText"] as? String ?? ""

        let lines = meta?["lines"] as? [[String: Any]] ?? []
        let firstLineItems = (lines.first?["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        let channel = ((firstLineItems.first?["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any])
            .flatMap { ($0["runs"] as? [[String: Any]])?.first?["text"] as? String } ?? ""
        let channelId = extractChannelId(from: tile, firstLineItems: firstLineItems)
        let channelAvatarURL = extractChannelAvatarURL(from: tile)

        let tileHeader = (tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any]
        let thumbs = (tileHeader?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let rawThumbURL = thumbs.last?["url"] as? String ?? ""
        let thumbURL = preferredThumbnailURL(videoId: videoId, fallbackURL: rawThumbURL)

        let overlays = tileHeader?["thumbnailOverlays"] as? [[String: Any]] ?? []
        let duration = overlays.compactMap {
            ((($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["text"] as? [String: Any])?["simpleText"] as? String)
        }.first

        var viewCount: String? = nil
        var publishedAt: String? = nil
        if lines.count > 1 {
            let items = (lines[1]["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
            for li in items {
                let text = ((li["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any])?["simpleText"] as? String ?? ""
                if text == "•" || text.isEmpty { continue }
                if text.contains("view") || text.contains("просмотр") {
                    viewCount = text
                } else if text.contains("ago") || text.contains("назад") || text.contains("hour")
                       || text.contains("day") || text.contains("week") || text.contains("month")
                       || text.contains("year") || text.contains("час") || text.contains("день")
                       || text.contains("нед") || text.contains("мес") || text.contains("лет") {
                    publishedAt = text
                }
            }
        }

        logThumbnailChoice(videoId: videoId, chosenURL: thumbURL, fallbackURL: rawThumbURL)

        return Video(id: videoId, title: title, channelId: channelId,
                     channelName: channel, channelAvatarURL: channelAvatarURL,
                     thumbnailURL: thumbURL, viewCount: viewCount,
                     publishedAt: publishedAt, duration: duration)
    }

    // MARK: - WEB search

    private static func parseSearchFeed(_ data: Data) -> [Video] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let twoCol = (json["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"] as? [String: Any],
              let primary = twoCol["primaryContents"] as? [String: Any],
              let sectionList = primary["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]],
              let section = sections.first,
              let items = (section["itemSectionRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> Video? in
            guard let vr = item["videoRenderer"] as? [String: Any] else { return nil }
            let videoId = vr["videoId"] as? String ?? ""
            let title = (vr["title"] as? [String: Any]).flatMap {
                ($0["runs"] as? [[String: Any]])?.first?["text"] as? String } ?? ""
            let channel = (vr["ownerText"] as? [String: Any]).flatMap {
                ($0["runs"] as? [[String: Any]])?.first?["text"] as? String } ?? ""
            let channelId = (vr["ownerText"] as? [String: Any]).flatMap {
                ($0["runs"] as? [[String: Any]])?.first?["navigationEndpoint"] as? [String: Any]
            }.flatMap { ($0["browseEndpoint"] as? [String: Any])?["browseId"] as? String }
            let viewCount = (vr["viewCountText"] as? [String: Any])?["simpleText"] as? String
            let thumbs = (vr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
            let rawThumbURL = thumbs.last?["url"] as? String ?? ""
            let thumbURL = preferredThumbnailURL(videoId: videoId, fallbackURL: rawThumbURL)
            let channelAvatarURL = (((vr["channelThumbnailSupportedRenderers"] as? [String: Any])?["channelThumbnailWithLinkRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])
                .flatMap { ($0["thumbnails"] as? [[String: Any]])?.last?["url"] as? String }
            guard !videoId.isEmpty else { return nil }
            logThumbnailChoice(videoId: videoId, chosenURL: thumbURL, fallbackURL: rawThumbURL)
            return Video(id: videoId, title: title, channelId: channelId,
                         channelName: channel, channelAvatarURL: channelAvatarURL,
                         thumbnailURL: thumbURL, viewCount: viewCount, publishedAt: nil, duration: nil)
        }
    }

    private static func parseChannelInfo(_ json: [String: Any], fallbackChannelId: String) -> ChannelInfo? {
        if let header = firstRenderer(in: json, named: "channelHeaderRenderer") {
            let avatarURL = extractThumbnailURL(from: header["avatar"]) ??
                extractThumbnailURL(from: header["thumbnail"]) ??
                extractThumbnailURL(from: header["image"])
            let title =
                simpleText(from: header["title"]) ??
                header["title"] as? String ??
                simpleText(from: header["headline"]) ??
                ""
            let subscriberCountText =
                simpleText(from: header["subscriberCountText"]) ??
                simpleText(from: header["metadata"]) ??
                simpleText(from: header["subtitle"])
            let channelId = header["channelId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                print("[Innertube] parseChannelInfo: channelHeaderRenderer matched for \(fallbackChannelId)")
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let avatarLockup = firstRenderer(in: json, named: "avatarLockupRenderer") {
            let avatarURL = extractThumbnailURL(from: avatarLockup["avatar"]) ??
                extractThumbnailURL(from: avatarLockup["thumbnail"])
            let title =
                simpleText(from: avatarLockup["title"]) ??
                simpleText(from: avatarLockup["text"]) ??
                ""
            let subscriberCountText =
                simpleText(from: avatarLockup["subtitle"]) ??
                simpleText(from: avatarLockup["accessibilityText"])
            let channelId = firstMatchingBrowseId(in: avatarLockup) ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                print("[Innertube] parseChannelInfo: avatarLockupRenderer matched for \(fallbackChannelId)")
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let header = firstRenderer(in: json, named: "c4TabbedHeaderRenderer") {
            let avatarURL = ((header["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                .last?["url"] as? String
            let title = header["title"] as? String ?? ""
            let subscriberCountText = simpleText(from: header["subscriberCountText"])
            let channelId = header["channelId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let metadata = firstRenderer(in: json, named: "channelMetadataRenderer") {
            let avatarURL = ((metadata["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                .last?["url"] as? String
            let title = metadata["title"] as? String ?? ""
            let channelId = metadata["externalId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: nil)
            }
        }

        if let header = findChannelHeaderCandidate(in: json) {
            let avatarURL =
                ((header["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String ??
                ((header["boxArt"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            let title =
                header["title"] as? String ??
                simpleText(from: header["title"]) ??
                simpleText(from: header["pageTitle"]) ??
                ""
            let subscriberCountText =
                simpleText(from: header["subscriberCountText"]) ??
                simpleText(from: header["metadata"]) ??
                simpleText(from: header["description"])
            let channelId = header["channelId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                print("[Innertube] parseChannelInfo: heuristic header matched for \(fallbackChannelId)")
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let tvBrowse = (json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any] {
            let topKeys = tvBrowse.keys.sorted().joined(separator: ", ")
            let headerKeys = (tvBrowse["header"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "nil"
            let contentKeys = (tvBrowse["content"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "nil"
            let rendererPaths = Array(collectRendererKeys(in: tvBrowse).prefix(30)).sorted().joined(separator: ", ")
            let thumbnailURLs = Array(collectThumbnailURLs(in: tvBrowse).prefix(10)).joined(separator: ", ")
            print("[Innertube] parseChannelInfo failed for \(fallbackChannelId). tvBrowse keys: \(topKeys). header keys: \(headerKeys). content keys: \(contentKeys)")
            print("[Innertube] channel renderers for \(fallbackChannelId): \(rendererPaths)")
            print("[Innertube] channel thumbnails for \(fallbackChannelId): \(thumbnailURLs)")
        } else {
            let topKeys = json.keys.sorted().joined(separator: ", ")
            print("[Innertube] parseChannelInfo failed for \(fallbackChannelId). top-level keys: \(topKeys)")
        }

        return nil
    }

    private static func parseSubscribeState(_ json: [String: Any]) -> (text: String?, isSubscribed: Bool) {
        guard let renderer = firstRenderer(in: json, named: "subscribeButtonRenderer") else {
            return (nil, false)
        }

        let isSubscribed = renderer["subscribed"] as? Bool ?? false
        let text = simpleText(from: renderer["buttonText"]) ??
            simpleText(from: renderer["subscribedButtonText"]) ??
            simpleText(from: renderer["unsubscribedButtonText"])

        return (text, isSubscribed)
    }

    private static func extractChannelId(from tile: [String: Any], firstLineItems: [[String: Any]]) -> String? {
        let candidatePaths: [[[String]]] = [
            [["lineItemRenderer"], ["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["onSelectCommand"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["command"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["text"], ["runs"], ["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["onSelectCommand"], ["browseEndpoint"], ["browseId"]]
        ]

        for item in firstLineItems {
            for path in candidatePaths {
                if let browseId = nestedValue(in: item, path: path) as? String,
                   browseId.hasPrefix("UC") {
                    return browseId
                }
            }
        }

        if let browseId = firstMatchingBrowseId(in: tile), browseId.hasPrefix("UC") {
            return browseId
        }

        return nil
    }

    private static func extractChannelAvatarURL(from tile: [String: Any]) -> String? {
        let candidatePaths: [[[String]]] = [
            [["metadata"], ["tileMetadataRenderer"], ["avatar"], ["thumbnails"]],
            [["metadata"], ["tileMetadataRenderer"], ["thumbnail"], ["thumbnails"]],
            [["metadata"], ["tileMetadataRenderer"], ["avatarThumbnail"], ["thumbnails"]],
            [["avatar"], ["thumbnails"]],
            [["channelThumbnailSupportedRenderers"], ["channelThumbnailWithLinkRenderer"], ["thumbnail"], ["thumbnails"]]
        ]

        for path in candidatePaths {
            if let thumbnails = nestedValue(in: tile, path: path) as? [[String: Any]],
               let url = thumbnails.last?["url"] as? String,
               !url.isEmpty {
                return url
            }
        }

        return nil
    }

    private static func firstRenderer(in value: Any, named key: String) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let renderer = dict[key] as? [String: Any] {
                return renderer
            }

            for child in dict.values {
                if let renderer = firstRenderer(in: child, named: key) {
                    return renderer
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let renderer = firstRenderer(in: child, named: key) {
                    return renderer
                }
            }
        }

        return nil
    }

    private static func firstMatchingBrowseId(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let browseId = dict["browseId"] as? String, browseId.hasPrefix("UC") {
                return browseId
            }

            for child in dict.values {
                if let browseId = firstMatchingBrowseId(in: child) {
                    return browseId
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let browseId = firstMatchingBrowseId(in: child) {
                    return browseId
                }
            }
        }

        return nil
    }

    private static func findChannelHeaderCandidate(in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            let hasAvatar = ((dict["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]]) != nil
            let hasBoxArt = ((dict["boxArt"] as? [String: Any])?["thumbnails"] as? [[String: Any]]) != nil
            let hasTitle = dict["title"] != nil || dict["pageTitle"] != nil
            let hasMetadata = dict["subscriberCountText"] != nil || dict["metadata"] != nil || dict["description"] != nil

            if (hasAvatar || hasBoxArt) && hasTitle && hasMetadata {
                return dict
            }

            for child in dict.values {
                if let candidate = findChannelHeaderCandidate(in: child) {
                    return candidate
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let candidate = findChannelHeaderCandidate(in: child) {
                    return candidate
                }
            }
        }

        return nil
    }

    private static func collectRendererKeys(in value: Any) -> Set<String> {
        var result = Set<String>()

        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if key.hasSuffix("Renderer") {
                    result.insert(key)
                }
                result.formUnion(collectRendererKeys(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(collectRendererKeys(in: child))
            }
        }

        return result
    }

    private static func collectThumbnailURLs(in value: Any) -> Set<String> {
        var result = Set<String>()

        if let dict = value as? [String: Any] {
            if let thumbnails = dict["thumbnails"] as? [[String: Any]] {
                for thumbnail in thumbnails {
                    if let url = thumbnail["url"] as? String, !url.isEmpty {
                        result.insert(url)
                    }
                }
            }

            for child in dict.values {
                result.formUnion(collectThumbnailURLs(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(collectThumbnailURLs(in: child))
            }
        }

        return result
    }

    private static func collectTileRenderers(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []

        if let dict = value as? [String: Any] {
            if let tile = dict["tileRenderer"] as? [String: Any] {
                result.append(tile)
            }

            for child in dict.values {
                result.append(contentsOf: collectTileRenderers(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(contentsOf: collectTileRenderers(in: child))
            }
        }

        return result
    }

    private static func extractThumbnailURL(from value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            if let thumbnails = dict["thumbnails"] as? [[String: Any]],
               let url = thumbnails.last?["url"] as? String,
               !url.isEmpty {
                return normalizeThumbnailURL(url)
            }

            for child in dict.values {
                if let url = extractThumbnailURL(from: child) {
                    return url
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let url = extractThumbnailURL(from: child) {
                    return url
                }
            }
        }

        return nil
    }

    private static func normalizeThumbnailURL(_ url: String) -> String {
        if url.hasPrefix("//") {
            return "https:\(url)"
        }
        return url
    }

    private static func preferredThumbnailURL(videoId: String, fallbackURL: String) -> String {
        guard !videoId.isEmpty else { return normalizeThumbnailURL(fallbackURL) }
        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    private static func logThumbnailChoice(videoId: String, chosenURL: String, fallbackURL: String) {
        _ = videoId
        _ = chosenURL
        _ = fallbackURL
    }

    private static func simpleText(from value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            if let text = dict["simpleText"] as? String, !text.isEmpty {
                return text
            }

            if let runs = dict["runs"] as? [[String: Any]] {
                let text = runs.compactMap { $0["text"] as? String }.joined()
                return text.isEmpty ? nil : text
            }
        }

        return nil
    }

    private static func nestedValue(in root: [String: Any], path: [[String]]) -> Any? {
        var current: Any? = root

        for keys in path {
            guard let dict = current as? [String: Any] else { return nil }

            var next: Any?
            for key in keys {
                if let value = dict[key] {
                    next = value
                    break
                }
            }

            guard let resolved = next else { return nil }
            current = resolved
        }

        return current
    }

    private static func buildCommentsContinuation(videoId: String, sortBy: Int, commentId: String?) -> String {
        let ctx = protoMessage([
            protoString(field: 2, value: videoId)
        ])

        let opts = protoMessage([
            protoString(field: 4, value: videoId),
            protoInt32(field: 6, value: sortBy),
            protoInt32(field: 15, value: 2),
            commentId.flatMap { protoString(field: 16, value: $0) }
        ].compactMap { $0 })

        let params = protoMessage([
            protoMessage(field: 4, value: opts),
            protoString(field: 8, value: "comments-section")
        ])

        let root = protoMessage([
            protoMessage(field: 2, value: ctx),
            protoInt32(field: 3, value: 6),
            protoMessage(field: 6, value: params)
        ])

        return percentEncode(base64URLEncoded(root))
    }

    private static func protoMessage(_ fields: [Data]) -> Data {
        fields.reduce(into: Data(), { $0.append($1) })
    }

    private static func protoMessage(field: Int, value: Data) -> Data {
        var data = Data()
        data.append(protoKey(field: field, wireType: 2))
        data.append(protoVarint(value.count))
        data.append(value)
        return data
    }

    private static func protoString(field: Int, value: String) -> Data {
        protoMessage(field: field, value: Data(value.utf8))
    }

    private static func protoInt32(field: Int, value: Int) -> Data {
        var data = Data()
        data.append(protoKey(field: field, wireType: 0))
        data.append(protoVarint(value))
        return data
    }

    private static func protoKey(field: Int, wireType: Int) -> Data {
        protoVarint((field << 3) | wireType)
    }

    private static func protoVarint(_ value: Int) -> Data {
        var data = Data()
        var current = UInt64(bitPattern: Int64(value))
        while current >= 0x80 {
            data.append(UInt8(current & 0x7F | 0x80))
            current >>= 7
        }
        data.append(UInt8(current))
        return data
    }

    private static func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    private static func collectCommentThreads(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []

        if let dict = value as? [String: Any] {
            if let renderer = dict["commentThreadRenderer"] as? [String: Any] {
                result.append(renderer)
            } else if dict["commentViewModel"] is [String: Any] {
                result.append(dict)
            }

            for child in dict.values {
                result.append(contentsOf: collectCommentThreads(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(contentsOf: collectCommentThreads(in: child))
            }
        }

        return result
    }

    private static func parseComment(from thread: [String: Any], mutations: [[String: Any]]) -> Comment? {
        guard let viewModel = thread["commentViewModel"] as? [String: Any] else { return nil }
        guard let commentId = viewModel["commentId"] as? String else { return nil }

        let commentKey = viewModel["commentKey"] as? String
        let toolbarStateKey = viewModel["toolbarStateKey"] as? String
        let toolbarSurfaceKey = viewModel["toolbarSurfaceKey"] as? String

        let commentMutation = mutations.first {
            (($0["payload"] as? [String: Any])?["commentEntityPayload"] as? [String: Any])?["key"] as? String == commentKey
        }.flatMap { ($0["payload"] as? [String: Any])?["commentEntityPayload"] as? [String: Any] }

        let toolbarStateMutation = mutations.first {
            (($0["payload"] as? [String: Any])?["engagementToolbarStateEntityPayload"] as? [String: Any])?["key"] as? String == toolbarStateKey
        }.flatMap { ($0["payload"] as? [String: Any])?["engagementToolbarStateEntityPayload"] as? [String: Any] }

        let toolbarSurfaceMutation = mutations.first {
            ($0["entityKey"] as? String) == toolbarSurfaceKey
        }.flatMap { ($0["payload"] as? [String: Any])?["engagementToolbarSurfaceEntityPayload"] as? [String: Any] }

        let author = (commentMutation?["author"] as? [String: Any]) ?? [:]
        let toolbar = (commentMutation?["toolbar"] as? [String: Any]) ?? [:]
        let properties = (commentMutation?["properties"] as? [String: Any]) ?? [:]
        let avatar = commentMutation?["avatar"] as? [String: Any]

        let authorName = (author["displayName"] as? String)
            ?? simpleText(from: author["displayText"])
            ?? "Unknown"
        let authorChannelId = author["channelId"] as? String
        let authorAvatarURL = extractThumbnailURL(from: avatar?["image"])
        let content = attributedText(from: properties["content"]) ?? simpleText(from: properties["content"]) ?? ""
        let publishedTime = properties["publishedTime"] as? String
        let likeCount = (toolbar["likeCountNotliked"] as? String)
            ?? (toolbar["likeCountLiked"] as? String)
            ?? simpleText(from: toolbar["likeCountA11y"])
        let replyCount = (toolbar["replyCount"] as? String)
            ?? simpleText(from: toolbar["replyCountA11y"])
        let isPinned = viewModel["pinnedText"] != nil || thread["pinnedCommentBadge"] != nil
        let isDeleted = (toolbarStateMutation?["isDeleted"] as? Bool) == true
        let hasSurface = toolbarSurfaceMutation != nil || toolbar.isEmpty == false

        guard !isDeleted, !content.isEmpty || hasSurface else { return nil }

        return Comment(id: commentId,
                       authorName: authorName,
                       authorChannelId: authorChannelId,
                       authorAvatarURL: authorAvatarURL,
                       content: content,
                       publishedTime: publishedTime,
                       likeCount: likeCount,
                       replyCount: replyCount,
                       isPinned: isPinned)
    }

    private static func attributedText(from value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let content = dict["content"] as? String, !content.isEmpty {
            return content
        }
        return simpleText(from: value)
    }

    private static func findCommentsContinuation(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let renderer = dict["continuationItemRenderer"] as? [String: Any],
               let endpoint = renderer["continuationEndpoint"] as? [String: Any],
               let command = endpoint["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String,
               !token.isEmpty {
                return token
            }

            for child in dict.values {
                if let token = findCommentsContinuation(in: child) {
                    return token
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let token = findCommentsContinuation(in: child) {
                    return token
                }
            }
        }

        return nil
    }

    private static func findCommentsTitle(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let renderer = dict["commentsHeaderRenderer"] as? [String: Any] {
                return simpleText(from: renderer["countText"])
                    ?? simpleText(from: renderer["commentsCount"])
                    ?? simpleText(from: renderer["titleText"])
            }

            if let renderer = dict["commentsEntryPointHeaderRenderer"] as? [String: Any] {
                return simpleText(from: renderer["commentCount"]) ?? simpleText(from: renderer["headerText"])
            }

            for child in dict.values {
                if let title = findCommentsTitle(in: child) {
                    return title
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let title = findCommentsTitle(in: child) {
                    return title
                }
            }
        }

        return nil
    }
}
