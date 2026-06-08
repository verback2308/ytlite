import Foundation

extension InnertubeClient {
    static func parseChannelTabPage(
        _ json: [String: Any]
    ) -> ChannelTabPage? {
        if json["continuationContents"] is [String: Any] {
            let page = parsePageJSON(json)
            return ChannelTabPage(feedPage: page, filterChips: [])
        }
        let items = selectedTabGridItems(from: json)
        let chips = extractFilterChips(from: json)
        let parsed = VideoRendererParserChain.parse(items: items)
        AppLog.innertube(
            "parseChannelTabPage videos=\(parsed.videos.count) cont=\(parsed.continuation != nil)"
        )
        let page = FeedPage(
            videos: parsed.videos,
            continuation: parsed.continuation
        )
        return ChannelTabPage(feedPage: page, filterChips: chips)
    }

    /// Parses continuation response for channel playlists tab.
    static func parseChannelPlaylistsNextPage(
        _ json: [String: Any]
    ) -> PlaylistsPage? {
        if let actions = json["onResponseReceivedActions"] as? [[String: Any]] {
            return parsePlaylistsFromActions(actions)
        }
        return parsePlaylistsFromContinuationContents(json)
    }

    private static func parsePlaylistsFromActions(
        _ actions: [[String: Any]]
    ) -> PlaylistsPage {
        var allPlaylists: [Playlist] = []
        var lastContinuation: String?
        for action in actions {
            guard let items = channelActionItems(from: action) else { continue }
            allPlaylists.append(contentsOf: lockupPlaylists(from: items))
            if let cont = items.lazy
                .compactMap({ VideoRendererParserChain.continuation(from: $0) })
                .first {
                lastContinuation = cont
            }
        }
        return PlaylistsPage(playlists: allPlaylists, continuation: lastContinuation)
    }

    private static func parsePlaylistsFromContinuationContents(
        _ json: [String: Any]
    ) -> PlaylistsPage? {
        guard let cc = json["continuationContents"] as? [String: Any],
              let gc = cc["gridContinuation"] as? [String: Any],
              let items = gc[JSONKey.items] as? [[String: Any]]
        else { return PlaylistsPage(playlists: [], continuation: nil) }
        return PlaylistsPage(
            playlists: lockupPlaylists(from: items),
            continuation: VideoRendererParserChain.continuation(from: items.last ?? [:])
        )
    }

    private static func lockupPlaylists(from items: [[String: Any]]) -> [Playlist] {
        items.compactMap { item -> Playlist? in
            guard let lockup = item["lockupViewModel"] as? [String: Any]
            else { return nil }
            return parseLockupPlaylist(lockup)
        }
    }
    static func parseChannelTabNextPage(_ json: [String: Any]) -> FeedPage? {
        // Sort response has multiple onResponseReceivedActions:
        //   [0] chipBarViewModel update, [1] actual video items
        // Pagination has a single appendContinuationItemsAction.
        guard let actions = json["onResponseReceivedActions"] as? [[String: Any]]
        else { return parsePageJSON(json) }
        var allVideos: [Video] = []
        var lastContinuation: String?
        for action in actions {
            guard let rawItems = channelActionItems(from: action)
            else { continue }
            let items = rawItems.compactMap { item -> [String: Any]? in
                if let content = item.digDict("richItemRenderer", JSONKey.content) {
                    return content
                }
                if item["continuationItemRenderer"] != nil {
                    return item
                }
                return nil
            }
            let parsed = VideoRendererParserChain.parse(items: items)
            allVideos.append(contentsOf: parsed.videos)
            if let cont = parsed.continuation { lastContinuation = cont }
        }
        let hasCont = lastContinuation != nil
        AppLog.innertube("channelTabNextPage: videos=\(allVideos.count) cont=\(hasCont)")
        if !allVideos.isEmpty || lastContinuation != nil {
            return FeedPage(videos: allVideos, continuation: lastContinuation)
        }
        return parsePageJSON(json)
    }

    private static func channelActionItems(
        from action: [String: Any]
    ) -> [[String: Any]]? {
        if let append = action["appendContinuationItemsAction"] as? [String: Any],
           let items = append["continuationItems"] as? [[String: Any]] {
            return items
        }
        if let reload = action["reloadContinuationItemsCommand"] as? [String: Any],
           let items = reload["continuationItems"] as? [[String: Any]] {
            return items
        }
        return nil
    }

    static func parseChannelPlaylists(
        _ json: [String: Any]
    ) -> PlaylistsPage? {
        let items = selectedTabGridItems(from: json)
        let playlists = items.compactMap { item -> Playlist? in
            guard let lockup = item["lockupViewModel"] as? [String: Any]
            else { return nil }
            return parseLockupPlaylist(lockup)
        }
        let continuation = items.lazy.compactMap {
            VideoRendererParserChain.continuation(from: $0)
        }.first
        let chips = extractFilterChips(from: json)
        return PlaylistsPage(
            playlists: playlists,
            continuation: continuation,
            filterChips: chips
        )
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
        if let richItems = tab.digArray(
            JSONKey.content, "richGridRenderer", JSONKey.contents
        ) {
            return richItems.compactMap { item -> [String: Any]? in
                if let content = item.digDict("richItemRenderer", JSONKey.content) {
                    return content
                }
                if item["continuationItemRenderer"] != nil {
                    return item
                }
                return nil
            }
        }
        let sections = tab.digArray(
            JSONKey.content, RendererKey.sectionList, JSONKey.contents
        ) ?? []
        return sections.reduce(into: [[String: Any]]()) { result, section in
            appendChannelGridItems(from: section, into: &result)
        }
    }

    static func selectedTabRenderer(
        from json: [String: Any]
    ) -> [String: Any]? {
        let tabs = json.digArray(
            JSONKey.contents, RendererKey.twoColumnBrowse, JSONKey.tabs
        ) ?? []
        return tabs
            .compactMap { $0[RendererKey.tab] as? [String: Any] }
            .first { ($0["selected"] as? Bool) == true }
    }

    static func extractFilterChips(
        from json: [String: Any]
    ) -> [ChannelFilterChip] {
        guard let tab = selectedTabRenderer(from: json),
              let content = tab[JSONKey.content] as? [String: Any]
        else { return [] }
        if let rich = content["richGridRenderer"] as? [String: Any],
           let chips = rich.digArray("header", "chipBarViewModel", "chips") {
            return parseChipBarChips(chips)
        }
        if let section = content["sectionListRenderer"] as? [String: Any] {
            if let chips = section.digArray("header", "chipBarViewModel", "chips") {
                return parseChipBarChips(chips)
            }
            return parseSortSubMenuChips(section)
        }
        return []
    }

    private static func parseChipBarChips(
        _ chips: [[String: Any]]
    ) -> [ChannelFilterChip] {
        chips.compactMap { item -> ChannelFilterChip? in
            guard let chip = item["chipViewModel"] as? [String: Any],
                  let label = chip["accessibilityLabel"] as? String,
                  let token = chip.digString(
                      "tapCommand",
                      "innertubeCommand",
                      "continuationCommand",
                      "token"
                  )
            else { return nil }
            return ChannelFilterChip(label: label, action: .continuation(token: token))
        }
    }

    private static func parseSortSubMenuChips(
        _ section: [String: Any]
    ) -> [ChannelFilterChip] {
        guard let items = section.digArray(
            "subMenu",
            "channelSubMenuRenderer",
            "sortSetting",
            "sortFilterSubMenuRenderer",
            "subMenuItems"
        ) else { return [] }
        return items.compactMap { item -> ChannelFilterChip? in
            guard let title = item["title"] as? String,
                  let endpoint = item.digDict(
                      "navigationEndpoint", "browseEndpoint"
                  ),
                  let channelId = endpoint["browseId"] as? String,
                  let params = endpoint["params"] as? String
            else { return nil }
            return ChannelFilterChip(
                label: title,
                action: .browse(ChannelBrowseAction(channelId: channelId, params: params))
            )
        }
    }

    static func appendChannelGridItems(
        from section: [String: Any],
        into items: inout [[String: Any]]
    ) {
        let contents = section.digArray(
            RendererKey.itemSection, JSONKey.contents
        ) ?? []
        contents.forEach { content in
            let gridItems = content.digArray(RendererKey.grid, JSONKey.items) ?? []
            items.append(contentsOf: gridItems)
        }
    }
}
