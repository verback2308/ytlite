import Foundation

class YouTubeAPIClient {

    private let api = APIClient()
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    private var authHeaders: [String: String] {
        ["Authorization": "Bearer \(Config.accessToken)"]
    }

    func searchVideos(query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void) {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "25"),
        ]
        guard let url = components.url else {
            completion(.failure(APIError.invalidURL)); return
        }
        api.get(url: url, headers: authHeaders) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let data):
                do {
                    let results = try YouTubeAPIClient.parseSearchResults(data)
                    completion(.success(results))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    func fetchPopularVideos(regionCode: String = "US", completion: @escaping (Result<[Video], Error>) -> Void) {
        var components = URLComponents(string: "\(baseURL)/videos")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "chart", value: "mostPopular"),
            URLQueryItem(name: "maxResults", value: "25"),
            URLQueryItem(name: "regionCode", value: regionCode),
        ]
        guard let url = components.url else { completion(.failure(APIError.invalidURL)); return }
        api.get(url: url, headers: authHeaders) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let items = json["items"] as? [[String: Any]]
                else { completion(.failure(APIError.decodingFailed)); return }
                let videos = items.compactMap { item -> Video? in
                    guard
                        let id = item["id"] as? String,
                        let snippet = item["snippet"] as? [String: Any],
                        let title = snippet["title"] as? String
                    else { return nil }
                    let channel = snippet["channelTitle"] as? String ?? ""
                    let thumbnails = snippet["thumbnails"] as? [String: Any] ?? [:]
                    let thumb = (thumbnails["maxres"] ?? thumbnails["high"] ?? thumbnails["medium"]) as? [String: Any]
                    let thumbURL = thumb?["url"] as? String ?? ""
                    return Video(id: id, title: title, channelName: channel,
                                 thumbnailURL: thumbURL, viewCount: nil,
                                 publishedAt: snippet["publishedAt"] as? String, duration: nil)
                }
                completion(.success(videos))
            }
        }
    }

    func fetchSubscriptionFeed(completion: @escaping (Result<[Video], Error>) -> Void) {
        fetchSubscribedChannelIds(maxChannels: 20) { [weak self] result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let channelIds):
                self?.fetchUploadsPlaylistIds(channelIds: channelIds) { result in
                    switch result {
                    case .failure(let e): completion(.failure(e))
                    case .success(let playlistIds):
                        self?.fetchRecentVideos(playlistIds: playlistIds, perChannel: 3, completion: completion)
                    }
                }
            }
        }
    }

    private func fetchSubscribedChannelIds(maxChannels: Int, completion: @escaping (Result<[String], Error>) -> Void) {
        var components = URLComponents(string: "\(baseURL)/subscriptions")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "\(maxChannels)"),
        ]
        guard let url = components.url else { completion(.failure(APIError.invalidURL)); return }
        api.get(url: url, headers: authHeaders) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let items = json["items"] as? [[String: Any]]
                else { completion(.failure(APIError.decodingFailed)); return }
                let ids = items.compactMap { ($0["snippet"] as? [String: Any]).flatMap { ($0["resourceId"] as? [String: Any])?["channelId"] as? String } }
                completion(.success(ids))
            }
        }
    }

    private func fetchUploadsPlaylistIds(channelIds: [String], completion: @escaping (Result<[String], Error>) -> Void) {
        var components = URLComponents(string: "\(baseURL)/channels")!
        components.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "id", value: channelIds.joined(separator: ",")),
            URLQueryItem(name: "maxResults", value: "50"),
        ]
        guard let url = components.url else { completion(.failure(APIError.invalidURL)); return }
        api.get(url: url, headers: authHeaders) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let data):
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let items = json["items"] as? [[String: Any]]
                else { completion(.failure(APIError.decodingFailed)); return }
                let ids = items.compactMap { item -> String? in
                    (item["contentDetails"] as? [String: Any])
                        .flatMap { ($0["relatedPlaylists"] as? [String: Any])?["uploads"] as? String }
                }
                completion(.success(ids))
            }
        }
    }

    private func fetchRecentVideos(playlistIds: [String], perChannel: Int, completion: @escaping (Result<[Video], Error>) -> Void) {
        var allVideos: [Video] = []
        let group = DispatchGroup()
        for playlistId in playlistIds {
            group.enter()
            var components = URLComponents(string: "\(baseURL)/playlistItems")!
            components.queryItems = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "playlistId", value: playlistId),
                URLQueryItem(name: "maxResults", value: "\(perChannel)"),
            ]
            guard let url = components.url else { group.leave(); continue }
            api.get(url: url, headers: authHeaders) { result in
                defer { group.leave() }
                guard case .success(let data) = result,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]] else { return }
                let videos = items.compactMap { item -> Video? in
                    guard let snippet = item["snippet"] as? [String: Any],
                          let resourceId = snippet["resourceId"] as? [String: Any],
                          let videoId = resourceId["videoId"] as? String,
                          let title = snippet["title"] as? String else { return nil }
                    let channel = snippet["channelTitle"] as? String ?? ""
                    let thumbnails = snippet["thumbnails"] as? [String: Any] ?? [:]
                    let thumb = (thumbnails["high"] ?? thumbnails["medium"] ?? thumbnails["default"]) as? [String: Any]
                    let thumbURL = thumb?["url"] as? String ?? ""
                    let publishedAt = snippet["publishedAt"] as? String
                    return Video(id: videoId, title: title, channelName: channel,
                                 thumbnailURL: thumbURL, viewCount: nil,
                                 publishedAt: publishedAt, duration: nil)
                }
                allVideos.append(contentsOf: videos)
            }
        }
        group.notify(queue: .main) {
            let sorted = allVideos.sorted { ($0.publishedAt ?? "") > ($1.publishedAt ?? "") }
            completion(.success(sorted))
        }
    }

    // MARK: - Parsing

    private static func parseSearchResults(_ data: Data) throws -> [SearchResult] {
        print("Search response: \(String(data: data, encoding: .utf8) ?? "nil")")
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["items"] as? [[String: Any]]
        else { throw APIError.decodingFailed }

        return items.compactMap { item -> SearchResult? in
            guard
                let id = (item["id"] as? [String: Any])?["videoId"] as? String,
                let snippet = item["snippet"] as? [String: Any],
                let title = snippet["title"] as? String,
                let channel = snippet["channelTitle"] as? String,
                let thumbnails = snippet["thumbnails"] as? [String: Any]
            else { return nil }

            let thumb = (thumbnails["high"] ?? thumbnails["medium"] ?? thumbnails["default"]) as? [String: Any]
            let thumbURL = thumb?["url"] as? String ?? ""
            return SearchResult(videoId: id, title: title, channelName: channel, thumbnailURL: thumbURL)
        }
    }

}
