import Foundation

// MARK: - Playlists

extension InnertubeClient {
    func executePlaylistsFetch(
        token: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        var body = tvContext
        body[JSONKey.browseId] = BrowseID.library
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistsFetch"
        ) { json -> [Playlist]? in
            Self.parsePlaylistTabs(json)
        } completion: { [weak self] result in
            guard let self else {
                return
            }
            self.handlePlaylistsFetchResult(
                result,
                token: token,
                completion: completion
            )
        }
    }

    func executePlaylistVideosFetch(
        playlistId: String,
        token: String,
        completion: @escaping (Result<[Video], Error>) -> Void
    ) {
        var body = tvContext
        body["browseId"] = "VL\(playlistId)"
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistVideos(\(playlistId))"
        ) { json -> [Video]? in
            let items = Self.playlistVideoItems(from: json)
            let videos: [Video] = items.compactMap { item in
                guard let tile = item["tileRenderer"] as? [String: Any],
                      let header = tile["header"] as? [String: Any],
                      let thr = header["tileHeaderRenderer"] as? [String: Any],
                      thr["thumbnailOverlays"] != nil
                else {
                    return nil
                }
                return InnertubeClient.parseTileRenderer(tile)
            }
            AppLog.innertube(
                "playlist \(playlistId): \(videos.count) videos"
            )
            return videos.isEmpty ? nil : videos
        } completion: { completion($0) }
    }
}

// MARK: - Private Playlist Helpers

private extension InnertubeClient {
    static func parsePlaylistTabs(
        _ json: [String: Any]
    ) -> [Playlist]? {
        let contents = json["contents"] as? [String: Any]
        let browse = contents?["tvBrowseRenderer"] as? [String: Any]
        let tabs = browse?["content"] as? [String: Any]
        let navRenderer = tabs?["tvSecondaryNavRenderer"] as? [String: Any]
        let sections = navRenderer?["sections"] as? [[String: Any]] ?? []
        let secRenderer = sections.first?["tvSecondaryNavSectionRenderer"]
        let secDict = secRenderer as? [String: Any]
        let allTabs = secDict?["tabs"] as? [[String: Any]] ?? []
        return allTabs.compactMap { tab in
            parsePlaylistTab(tab)
        }
    }

    static func parsePlaylistTab(
        _ tab: [String: Any]
    ) -> Playlist? {
        guard let tr = tab["tabRenderer"] as? [String: Any],
              let title = tr["title"] as? String,
              let endpoint = tr["endpoint"] as? [String: Any],
              let browse = endpoint["browseEndpoint"] as? [String: Any],
              let params = browse["params"] as? String,
              let playlistId = extractPlaylistIdFromParams(params)
        else {
            return nil
        }
        return Playlist(
            id: playlistId,
            title: title,
            description: "",
            thumbnailURL: nil,
            itemCount: nil
        )
    }

    static func playlistVideoItems(
        from json: [String: Any]
    ) -> [[String: Any]] {
        let contents = json["contents"] as? [String: Any]
        let browse = contents?["tvBrowseRenderer"] as? [String: Any]
        let rightCol = browse?["content"] as? [String: Any]
        let surface = rightCol?["tvSurfaceContentRenderer"] as? [String: Any]
        let surfaceContent = surface?["content"] as? [String: Any]
        let twoCol = surfaceContent?["twoColumnRenderer"] as? [String: Any]
        let right = twoCol?["rightColumn"] as? [String: Any]
        let listRenderer = right?["playlistVideoListRenderer"] as? [String: Any]
        return listRenderer?["contents"] as? [[String: Any]] ?? []
    }

    static func extractPlaylistIdFromParams(
        _ params: String
    ) -> String? {
        guard let urlDecoded = params.removingPercentEncoding,
              let data = Data(
                  base64Encoded: urlDecoded,
                  options: .ignoreUnknownCharacters
              )
        else {
            return nil
        }
        let bytes = [UInt8](data)
        var offset = 0
        while offset < bytes.count {
            let tagResult = decodeVarint(bytes: bytes, offset: &offset)
            let fieldNum = tagResult >> 3
            let wireType = tagResult & 0x7
            switch wireType {
            case 0:
                skipVarint(bytes: bytes, offset: &offset)
            case 2:
                if let id = decodeLengthDelimited(
                    bytes: bytes,
                    offset: &offset,
                    fieldNum: fieldNum
                ) {
                    return id
                }
            default:
                return nil
            }
        }
        return nil
    }

    static func decodeVarint(
        bytes: [UInt8],
        offset: inout Int
    ) -> UInt64 {
        var value: UInt64 = 0
        var shift = 0
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7f) << shift
            shift += 7
            if byte & 0x80 == 0 {
                break
            }
        }
        return value
    }

    static func skipVarint(
        bytes: [UInt8],
        offset: inout Int
    ) {
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte & 0x80 == 0 {
                break
            }
        }
    }

    static func decodeLengthDelimited(
        bytes: [UInt8],
        offset: inout Int,
        fieldNum: UInt64
    ) -> String? {
        guard offset < bytes.count else {
            return nil
        }
        let len = Int(bytes[offset])
        offset += 1
        guard offset + len <= bytes.count else {
            return nil
        }
        let slice = bytes[offset..<offset + len]
        if fieldNum == 70,
           let id = String(bytes: slice, encoding: .utf8),
           id.hasPrefix("PL") || id == "LL" {
            return id
        }
        offset += len
        return nil
    }

    func handlePlaylistsFetchResult(
        _ result: Result<[Playlist], Error>,
        token: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            completion(.failure(error))
        case .success(let playlists):
            let watchLater = Playlist(
                id: "WL",
                title: "Watch Later",
                description: "",
                thumbnailURL: nil,
                itemCount: nil
            )
            let all = [watchLater] + playlists
            guard !all.isEmpty else {
                completion(.success(all))
                return
            }
            fetchAllThumbnails(
                playlists: all,
                token: token,
                completion: completion
            )
        }
    }

    func fetchAllThumbnails(
        playlists: [Playlist],
        token: String,
        completion: @escaping (Result<[Playlist], Error>) -> Void
    ) {
        let group = DispatchGroup()
        var thumbnails: [String: String] = [:]
        let lock = NSLock()
        for playlist in playlists {
            group.enter()
            fetchPlaylistFirstThumbnail(
                playlistId: playlist.id,
                token: token
            ) { url in
                if let url {
                    lock.lock()
                    thumbnails[playlist.id] = url
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .global()) {
            let result = playlists.map { pl in
                Playlist(
                    id: pl.id,
                    title: pl.title,
                    description: pl.description,
                    thumbnailURL: thumbnails[pl.id],
                    itemCount: pl.itemCount
                )
            }
            completion(.success(result))
        }
    }

    func fetchPlaylistFirstThumbnail(
        playlistId: String,
        token: String,
        completion: @escaping (String?) -> Void
    ) {
        var body = tvContext
        body["browseId"] = "VL\(playlistId)"
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.browse)",
            body: body,
            headers: authHeaders(token: token),
            logTag: "playlistThumb(\(playlistId))"
        ) { json -> String? in
            let items = Self.playlistVideoItems(from: json)
            for item in items {
                if let tile = item["tileRenderer"] as? [String: Any],
                   let video = InnertubeClient.parseTileRenderer(tile) {
                    return video.thumbnailURL
                }
            }
            return nil
        } completion: { result in
            completion(try? result.get())
        }
    }
}
