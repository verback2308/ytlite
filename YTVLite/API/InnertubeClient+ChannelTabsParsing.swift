import Foundation

extension InnertubeClient {
    static func parseChannelTabPage(
        _ json: [String: Any]
    ) -> FeedPage? {
        if json["continuationContents"] is [String: Any] {
            return parsePageJSON(json)
        }
        let items = selectedTabGridItems(from: json)
        let parsed = VideoRendererParserChain.parse(items: items)
        return FeedPage(
            videos: parsed.videos,
            continuation: parsed.continuation
        )
    }

    static func parseChannelPlaylists(
        _ json: [String: Any]
    ) -> [Playlist]? {
        selectedTabGridItems(from: json).compactMap { item in
            guard let lockup = item["lockupViewModel"] as? [String: Any]
            else {
                return nil
            }
            return parseLockupPlaylist(lockup)
        }
    }

    static func parseLockupPlaylist(
        _ lockup: [String: Any]
    ) -> Playlist? {
        guard let playlistId = lockup["contentId"] as? String,
              let title = playlistTitle(from: lockup) else {
            return nil
        }
        return Playlist(
            id: playlistId,
            title: title,
            description: "",
            thumbnailURL: playlistThumbnailURL(from: lockup),
            itemCount: playlistBadgeCount(from: lockup)
        )
    }

    static func selectedTabGridItems(
        from json: [String: Any]
    ) -> [[String: Any]] {
        guard let tab = selectedTabRenderer(from: json)
        else { return [] }
        // Path 1: richGridRenderer (Videos, Live tabs)
        if let richItems = tab.digArray(
            JSONKey.content, "richGridRenderer", JSONKey.contents
        ) {
            return richItems.compactMap { item -> [String: Any]? in
                if let content = item.digDict("richItemRenderer", JSONKey.content) {
                    return content
                }
                // Pass continuation items through so the parser chain can extract the token
                if item["continuationItemRenderer"] != nil {
                    return item
                }
                return nil
            }
        }
        // Path 2: sectionListRenderer → itemSectionRenderer → gridRenderer (Playlists)
        let sections = tab.digArray(
            JSONKey.content,
            RendererKey.sectionList,
            JSONKey.contents
        ) ?? []
        return sections.reduce(into: [[String: Any]]()) { result, section in
            appendChannelGridItems(from: section, into: &result)
        }
    }

    static func selectedTabRenderer(
        from json: [String: Any]
    ) -> [String: Any]? {
        let tabs = json.digArray(
            JSONKey.contents,
            RendererKey.twoColumnBrowse,
            JSONKey.tabs
        ) ?? []
        return tabs
            .compactMap { $0[RendererKey.tab] as? [String: Any] }
            .first { ($0["selected"] as? Bool) == true }
    }

    static func appendChannelGridItems(
        from section: [String: Any],
        into items: inout [[String: Any]]
    ) {
        let contents = section.digArray(
            RendererKey.itemSection,
            JSONKey.contents
        ) ?? []
        contents.forEach { content in
            let gridItems = content.digArray(
                RendererKey.grid,
                JSONKey.items
            ) ?? []
            items.append(contentsOf: gridItems)
        }
    }

    static func playlistTitle(
        from lockup: [String: Any]
    ) -> String? {
        let title = lockup.digString(
            "metadata",
            "lockupMetadataViewModel",
            JSONKey.title,
            JSONKey.content
        ) ?? ""
        return title.isEmpty ? nil : title
    }

    static func playlistThumbnailURL(
        from lockup: [String: Any]
    ) -> String? {
        let url = lockup.digString(
            "contentImage",
            "collectionThumbnailViewModel",
            "primaryThumbnail",
            "thumbnailViewModel",
            "image",
            "sources",
            0,
            JSONKey.url
        )
        return url.map(normalizeThumbnailURL)
    }

    static func playlistBadgeCount(
        from lockup: [String: Any]
    ) -> Int? {
        let text = lockup.digString(
            "contentImage",
            "collectionThumbnailViewModel",
            "primaryThumbnail",
            "thumbnailViewModel",
            "overlays",
            0,
            "thumbnailOverlayBadgeViewModel",
            "thumbnailBadges",
            0,
            "thumbnailBadgeViewModel",
            JSONKey.text
        )
        return playlistItemCount(from: text)
    }

    static func playlistItemCount(
        from text: String?
    ) -> Int? {
        guard let text else {
            return nil
        }
        let digits = text.filter { $0.isNumber }
        return Int(digits)
    }
}
