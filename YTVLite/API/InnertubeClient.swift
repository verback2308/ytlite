import Foundation

class InnertubeClient {

    private let api = APIClient()
    private let baseURL = "https://www.youtube.com/youtubei/v1"
    private let clientContext: [String: Any] = [
        "context": [
            "client": [
                "clientName": "WEB",
                "clientVersion": "2.20231121.08.00",
                "hl": "en",
                "gl": "US"
            ]
        ]
    ]

    func fetchHomeFeed(completion: @escaping (Result<[Video], Error>) -> Void) {
        browse(browseId: "FEwhat_to_watch", completion: completion)
    }

    func searchVideos(query: String, completion: @escaping (Result<[Video], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/search") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = clientContext
        body["query"] = query

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                let videos = InnertubeClient.parseSearchResults(data)
                completion(.success(videos))
            }
        }
    }

    // MARK: - Private

    private func browse(browseId: String, completion: @escaping (Result<[Video], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/browse") else {
            completion(.failure(APIError.invalidURL)); return
        }
        var body = clientContext
        body["browseId"] = browseId

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json"]
        api.post(url: url, headers: headers, body: bodyData) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                let videos = InnertubeClient.parseHomeFeed(data)
                completion(.success(videos))
            }
        }
    }

    // MARK: - Parsing

    private static func parseHomeFeed(_ data: Data) -> [Video] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[Innertube] Failed to parse JSON")
            return []
        }

        guard
            let contents = json["contents"] as? [String: Any],
            let twoCol = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
            let tabs = twoCol["tabs"] as? [[String: Any]],
            let tab = tabs.first,
            let tabRenderer = tab["tabRenderer"] as? [String: Any],
            let tabContent = tabRenderer["content"] as? [String: Any],
            let richGrid = tabContent["richGridRenderer"] as? [String: Any],
            let gridContents = richGrid["contents"] as? [[String: Any]]
        else {
            print("[Innertube] Failed to navigate JSON path. Top-level keys: \(json.keys.joined(separator: ", "))")
            return []
        }

        print("[Innertube] Grid items: \(gridContents.count), first keys: \(gridContents.first?.keys.joined(separator: ", ") ?? "none")")
        var videos: [Video] = []
        for item in gridContents {
            // Direct video item
            if let richItem = item["richItemRenderer"] as? [String: Any],
               let content = richItem["content"] as? [String: Any],
               let vr = content["videoRenderer"] as? [String: Any],
               let video = parseVideoRenderer(vr) {
                videos.append(video)
            }
            // Section containing a shelf of videos
            if let section = item["richSectionRenderer"] as? [String: Any],
               let content = section["content"] as? [String: Any],
               let shelf = content["richShelfRenderer"] as? [String: Any],
               let shelfContents = shelf["contents"] as? [[String: Any]] {
                for shelfItem in shelfContents {
                    if let richItem = shelfItem["richItemRenderer"] as? [String: Any],
                       let itemContent = richItem["content"] as? [String: Any],
                       let vr = itemContent["videoRenderer"] as? [String: Any],
                       let video = parseVideoRenderer(vr) {
                        videos.append(video)
                    }
                }
            }
        }
        print("[Innertube] Parsed \(videos.count) videos from home feed")
        return videos
    }

    private static func parseSearchResults(_ data: Data) -> [Video] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        guard
            let contents = json["contents"] as? [String: Any],
            let twoCol = contents["twoColumnSearchResultsRenderer"] as? [String: Any],
            let primaryContents = twoCol["primaryContents"] as? [String: Any],
            let sectionList = primaryContents["sectionListRenderer"] as? [String: Any],
            let sections = sectionList["contents"] as? [[String: Any]],
            let section = sections.first,
            let itemSection = section["itemSectionRenderer"] as? [String: Any],
            let items = itemSection["contents"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> Video? in
            guard let videoRenderer = item["videoRenderer"] as? [String: Any] else { return nil }
            return parseVideoRenderer(videoRenderer)
        }
    }

    private static func parseVideoRenderer(_ v: [String: Any]) -> Video? {
        guard let videoId = v["videoId"] as? String else { return nil }

        let title = (v["title"] as? [String: Any]).flatMap { t in
            (t["runs"] as? [[String: Any]])?.first?["text"] as? String
        } ?? ""

        let channelName = (v["ownerText"] as? [String: Any]).flatMap { t in
            (t["runs"] as? [[String: Any]])?.first?["text"] as? String
        } ?? ""

        let viewCount = (v["viewCountText"] as? [String: Any])?["simpleText"] as? String

        let thumbnails = (v["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let thumbURL = thumbnails.last?["url"] as? String ?? ""

        return Video(id: videoId, title: title, channelName: channelName,
                     thumbnailURL: thumbURL, viewCount: viewCount,
                     publishedAt: nil, duration: nil)
    }
}
