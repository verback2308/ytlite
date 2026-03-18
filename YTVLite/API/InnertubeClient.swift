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

        return Video(id: videoId, title: title, channelName: channel,
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
            let viewCount = (vr["viewCountText"] as? [String: Any])?["simpleText"] as? String
            let thumbs = (vr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
            let thumbURL = thumbs.last?["url"] as? String ?? ""
            guard !videoId.isEmpty else { return nil }
            return Video(id: videoId, title: title, channelName: channel,
                         thumbnailURL: thumbURL, viewCount: viewCount, publishedAt: nil, duration: nil)
        }
    }
}
