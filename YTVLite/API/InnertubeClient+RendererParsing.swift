import Foundation

// MARK: - Renderer Parsing
extension InnertubeClient {
    static func parseWebVideoRenderer(
        _ vr: [String: Any]
    ) -> Video? {
        guard let videoId = vr[JSONKey.videoId]
            as? String
        else {
            return nil
        }
        let title = simpleText(
            from: vr[JSONKey.title]
        ) ?? ""
        guard !title.isEmpty else {
            return nil
        }
        return buildWebVideo(
            videoId: videoId,
            title: title,
            renderer: vr
        )
    }

    static func parseTileRenderer(
        _ tile: [String: Any]
    ) -> Video? {
        guard let videoId = tile.digString(
            "onSelectCommand",
            "watchEndpoint",
            JSONKey.videoId
        ) else {
            return nil
        }
        let meta = tile.digDict(
            "metadata",
            RendererKey.tileMetadata
        )
        let title = simpleText(
            from: meta?[JSONKey.title]
        ) ?? ""
        return buildTileVideo(
            videoId: videoId,
            title: title,
            tile: tile,
            meta: meta
        )
    }

    static func parseGridVideoRenderer(
        _ vr: [String: Any]
    ) -> Video? {
        guard let videoId = vr[JSONKey.videoId] as? String else {
            return nil
        }
        let title = simpleText(from: vr[JSONKey.title]) ?? ""
        guard !title.isEmpty else {
            return nil
        }
        let rawURL = vr.thumbnailURL() ?? ""
        let thumb = preferredThumbnailURL(videoId: videoId, fallbackURL: rawURL)
        let isLive = checkOverlayLive(vr["thumbnailOverlays"])
        let channelName = gridChannelName(from: vr)
        let duration = isLive ? nil : gridDuration(from: vr)
        logThumbnailChoice(videoId: videoId, chosenURL: thumb, fallbackURL: rawURL)
        return Video(
            id: videoId,
            title: title,
            channelId: gridChannelId(from: vr),
            channelName: channelName,
            channelAvatarURL: nil,
            thumbnailURL: thumb,
            viewCount: simpleText(from: vr["viewCountText"]),
            publishedAt: simpleText(from: vr["publishedTimeText"]),
            duration: duration,
            isLive: isLive
        )
    }

    static func parseRadioRenderer(
        _ rr: [String: Any]
    ) -> Video? {
        guard let videoId = rr["videoId"]
            as? String
        else {
            return nil
        }
        let title = simpleText(
            from: rr["title"]
        ) ?? "YouTube Mix"
        let thumbURL = radioThumbURL(
            rr, videoId: videoId
        )
        let videoCount = extractVideoCount(
            from: rr["videoCountText"]
        )
        return Video(
            id: videoId,
            title: title,
            channelId: nil,
            channelName: "YouTube Mix",
            channelAvatarURL: nil,
            thumbnailURL: thumbURL,
            viewCount: videoCount,
            publishedAt: nil,
            duration: "Mix",
            isLive: false
        )
    }

    static func parsePlaylistRenderer(
        _ pr: [String: Any]
    ) -> Video? {
        guard let videoId = resolvePlaylistVideoId(
            pr
        ) else {
            return nil
        }
        let title = simpleText(
            from: pr["title"]
        ) ?? "Playlist"
        let thumbURL = playlistThumbURL(
            pr, videoId: videoId
        )
        let count = pr["videoCount"] as? String
        return Video(
            id: videoId,
            title: title,
            channelId: nil,
            channelName: "Playlist",
            channelAvatarURL: nil,
            thumbnailURL: thumbURL,
            viewCount: count.map { "\($0) videos" },
            publishedAt: nil,
            duration: nil,
            isLive: false
        )
    }
}

// MARK: - Private Renderer Helpers
private extension InnertubeClient {
    static func buildWebVideo(
        videoId: String,
        title: String,
        renderer vr: [String: Any]
    ) -> Video {
        let rawURL = vr.thumbnailURL() ?? ""
        let thumb = preferredThumbnailURL(videoId: videoId, fallbackURL: rawURL)
        let chName = vr.digString("ownerText", JSONKey.runs, 0, JSONKey.text) ?? ""
        let chId = webChannelId(from: vr)
        let isLive = checkOverlayLive(vr["thumbnailOverlays"])
        let dur: String? = isLive ? nil : webDuration(from: vr)
        let views = simpleText(from: vr["viewCountText"])
        let published = simpleText(from: vr["publishedTimeText"])
        logThumbnailChoice(videoId: videoId, chosenURL: thumb, fallbackURL: rawURL)
        return Video(
            id: videoId,
            title: title,
            channelId: chId,
            channelName: chName,
            channelAvatarURL: nil,
            thumbnailURL: thumb,
            viewCount: views,
            publishedAt: published,
            duration: dur,
            isLive: isLive
        )
    }

    static func webChannelId(
        from vr: [String: Any]
    ) -> String? {
        vr.digString(
            "ownerText",
            JSONKey.runs,
            0,
            "navigationEndpoint",
            "browseEndpoint",
            JSONKey.browseId
        )
    }

    static func webDuration(
        from vr: [String: Any]
    ) -> String? {
        simpleText(from: vr["lengthText"])
            ?? vr.digString(
                "lengthText",
                "accessibility",
                "accessibilityData",
                "label"
            )
    }

    static func gridChannelName(
        from vr: [String: Any]
    ) -> String {
        vr.digString("shortBylineText", JSONKey.runs, 0, JSONKey.text) ?? ""
    }

    static func gridChannelId(
        from vr: [String: Any]
    ) -> String? {
        vr.digString(
            "shortBylineText",
            JSONKey.runs,
            0,
            "navigationEndpoint",
            "browseEndpoint",
            JSONKey.browseId
        )
    }

    static func gridDuration(
        from vr: [String: Any]
    ) -> String? {
        let overlays = vr["thumbnailOverlays"] as? [[String: Any]] ?? []
        return overlays.compactMap { overlay in
            let renderer = overlay[RendererKey.thumbnailOverlayTimeStatus]
                as? [String: Any]
            return simpleText(from: renderer?[JSONKey.text])
        }.first
    }

    static func radioThumbURL(
        _ rr: [String: Any],
        videoId: String
    ) -> String {
        let thumbs = (rr["thumbnail"]
            as? [String: Any])?["thumbnails"]
            as? [[String: Any]] ?? []
        return thumbs.last?["url"] as? String
            ?? AppURLs.YouTube
                .thumbnailURL(videoId: videoId)
    }

    static func playlistThumbURL(
        _ pr: [String: Any],
        videoId: String
    ) -> String {
        let thumbs = (pr["thumbnail"]
            as? [String: Any])?["thumbnails"]
            as? [[String: Any]] ?? []
        return thumbs.last?["url"] as? String
            ?? AppURLs.YouTube
                .thumbnailURL(videoId: videoId)
    }

    static func extractVideoCount(
        from obj: Any?
    ) -> String? {
        guard let dict = obj as? [String: Any]
        else {
            return nil
        }
        if let simple = dict["simpleText"]
            as? String {
            return simple
        }
        let runs = dict["runs"]
            as? [[String: Any]]
        return runs?
            .compactMap { $0["text"] as? String }
            .joined()
    }

    static func resolvePlaylistVideoId(
        _ pr: [String: Any]
    ) -> String? {
        if let vid = pr["firstVideoId"]
            as? String {
            return vid
        }
        let navEp = pr["navigationEndpoint"]
            as? [String: Any]
        if let vid = (navEp?["watchEndpoint"]
            as? [String: Any])?["videoId"]
            as? String {
            return vid
        }
        let videos = pr["videos"]
            as? [[String: Any]]
        return videos?.first.flatMap {
            ($0["childVideoRenderer"]
                as? [String: Any])?["videoId"]
                as? String
        }
    }
}
