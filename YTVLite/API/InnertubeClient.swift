import Foundation

final class InnertubeClient: VideoService {

    private let api = APIClient()
    private let baseURL = "https://www.youtube.com/youtubei/v1"

    private let webContext: [String: Any] = [
        "context": ["client": ["clientName": "WEB", "clientVersion": "2.20231121.08.00", "hl": "en", "gl": "US"]]
    ]
    private let tvContext: [String: Any] = [
        "context": ["client": ["clientName": "TVHTML5", "clientVersion": "7.20230405.08.01", "hl": "en", "gl": "US"]]
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

    // MARK: - JSON parsing

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
        let thumbURL = thumbs.last?["url"] as? String ?? ""

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
            let thumbURL = thumbs.last?["url"] as? String ?? ""
            let channelAvatarURL = (((vr["channelThumbnailSupportedRenderers"] as? [String: Any])?["channelThumbnailWithLinkRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])
                .flatMap { ($0["thumbnails"] as? [[String: Any]])?.last?["url"] as? String }
            guard !videoId.isEmpty else { return nil }
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
}
