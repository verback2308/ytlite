import Foundation

extension InnertubeClient {
    static func parseSearchFeed(
        _ data: Data
    ) -> [Video] {
        guard let items = searchFeedItems(from: data)
        else {
            return []
        }
        return items.compactMap { parseVideoRenderer($0) }
    }
}

private extension InnertubeClient {
    static func searchFeedItems(
        from data: Data
    ) -> [[String: Any]]? {
        guard let json = try? JSONSerialization
            .jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let contents = json["contents"] as? [String: Any]
        let twoCol = contents?[
            "twoColumnSearchResultsRenderer"
        ] as? [String: Any]
        let primary = twoCol?[
            "primaryContents"
        ] as? [String: Any]
        let sectionList = primary?[
            "sectionListRenderer"
        ] as? [String: Any]
        let sections = sectionList?[
            "contents"
        ] as? [[String: Any]]
        let section = sections?.first?[
            "itemSectionRenderer"
        ] as? [String: Any]
        return section?[
            "contents"
        ] as? [[String: Any]]
    }

    static func parseVideoRenderer(
        _ item: [String: Any]
    ) -> Video? {
        guard let vr = item["videoRenderer"]
            as? [String: Any]
        else {
            return nil
        }
        let videoId = vr["videoId"] as? String ?? ""
        guard !videoId.isEmpty
        else {
            return nil
        }
        let rawURL = thumbnailsLastURL(vr["thumbnail"])
        let thumbURL = preferredThumbnailURL(
            videoId: videoId,
            fallbackURL: rawURL
        )
        logThumbnailChoice(
            videoId: videoId,
            chosenURL: thumbURL,
            fallbackURL: rawURL
        )
        return buildVideo(
            from: vr,
            videoId: videoId,
            thumbURL: thumbURL
        )
    }

    static func buildVideo(
        from vr: [String: Any],
        videoId: String,
        thumbURL: String
    ) -> Video {
        Video(
            id: videoId,
            title: videoTitle(from: vr),
            channelId: videoChannelId(from: vr),
            channelName: videoChannel(from: vr),
            channelAvatarURL: videoChannelAvatar(vr),
            thumbnailURL: thumbURL,
            viewCount: videoViewCount(from: vr),
            publishedAt: videoPublishedAt(from: vr),
            duration: overlayDuration(from: vr),
            isLive: overlayIsLive(from: vr)
        )
    }

    static func videoTitle(
        from vr: [String: Any]
    ) -> String {
        let titleObj = vr["title"] as? [String: Any]
        let runs = titleObj?["runs"]
            as? [[String: Any]]
        return runs?.first?["text"] as? String ?? ""
    }

    static func videoChannel(
        from vr: [String: Any]
    ) -> String {
        let ownerObj = vr["ownerText"]
            as? [String: Any]
        let runs = ownerObj?["runs"]
            as? [[String: Any]]
        return runs?.first?["text"] as? String ?? ""
    }

    static func videoChannelId(
        from vr: [String: Any]
    ) -> String? {
        let ownerObj = vr["ownerText"]
            as? [String: Any]
        let runs = ownerObj?["runs"]
            as? [[String: Any]]
        let nav = runs?.first?[
            "navigationEndpoint"
        ] as? [String: Any]
        let browse = nav?["browseEndpoint"]
            as? [String: Any]
        return browse?["browseId"] as? String
    }

    static func videoViewCount(
        from vr: [String: Any]
    ) -> String? {
        let obj = vr["viewCountText"] as? [String: Any]
        if let text = obj?["simpleText"] as? String {
            return text
        }
        let runs = obj?["runs"] as? [[String: Any]]
        return runs?
            .compactMap { $0["text"] as? String }
            .joined()
    }

    static func videoPublishedAt(
        from vr: [String: Any]
    ) -> String? {
        let obj = vr["publishedTimeText"]
            as? [String: Any]
        return obj?["simpleText"] as? String
    }

    static func videoChannelAvatar(
        _ vr: [String: Any]
    ) -> String? {
        let ctsr = vr[
            "channelThumbnailSupportedRenderers"
        ] as? [String: Any]
        let ctlr = ctsr?[
            "channelThumbnailWithLinkRenderer"
        ] as? [String: Any]
        let thumb = ctlr?["thumbnail"]
            as? [String: Any]
        let thumbs = thumb?["thumbnails"]
            as? [[String: Any]]
        return thumbs?.last?["url"] as? String
    }

    static func overlayIsLive(
        from vr: [String: Any]
    ) -> Bool {
        let overlays = vr["thumbnailOverlays"]
            as? [[String: Any]] ?? []
        return overlays.contains {
            let rdr = $0[
                "thumbnailOverlayTimeStatusRenderer"
            ] as? [String: Any]
            return rdr?["style"] as? String == "LIVE"
        }
    }

    static func overlayDuration(
        from vr: [String: Any]
    ) -> String? {
        let overlays = vr["thumbnailOverlays"]
            as? [[String: Any]] ?? []
        let renderer = overlays.compactMap {
            $0["thumbnailOverlayTimeStatusRenderer"]
                as? [String: Any]
        }.first
        let text = renderer?["text"] as? [String: Any]
        return text?["simpleText"] as? String
    }
}
