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
        // Channel tab continuations use onResponseReceivedActions
        if let actions = json["onResponseReceivedActions"] as? [[String: Any]],
           let action = actions.first,
           let append = action["appendContinuationItemsAction"] as? [String: Any],
           let rawItems = append["continuationItems"] as? [[String: Any]] {
            let playlists = rawItems.compactMap { item -> Playlist? in
                guard let lockup = item["lockupViewModel"] as? [String: Any]
                else { return nil }
                return parseLockupPlaylist(lockup)
            }
            let continuation = rawItems.lazy.compactMap {
                VideoRendererParserChain.continuation(from: $0)
            }.first
            return PlaylistsPage(playlists: playlists, continuation: continuation)
        }
        // Fallback: standard continuationContents
        if let cc = json["continuationContents"] as? [String: Any],
           let gc = cc["gridContinuation"] as? [String: Any],
           let items = gc[JSONKey.items] as? [[String: Any]] {
            let playlists = items.compactMap { item -> Playlist? in
                guard let lockup = item["lockupViewModel"] as? [String: Any]
                else { return nil }
                return parseLockupPlaylist(lockup)
            }
            return PlaylistsPage(
                playlists: playlists,
                continuation: VideoRendererParserChain.continuation(
                    from: items.last ?? [:]
                )
            )
        }
        return PlaylistsPage(playlists: [], continuation: nil)
    }
    static func parseChannelTabNextPage(_ json: [String: Any]) -> FeedPage? {
        // Channel tab continuations: onResponseReceivedActions[0]
        //   .appendContinuationItemsAction.continuationItems[]
        if let actions = json["onResponseReceivedActions"] as? [[String: Any]],
           let action = actions.first,
           let append = action["appendContinuationItemsAction"] as? [String: Any],
           let rawItems = append["continuationItems"] as? [[String: Any]] {
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
            return FeedPage(videos: parsed.videos, continuation: parsed.continuation)
        }
        return parsePageJSON(json)
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
        return PlaylistsPage(playlists: playlists, continuation: continuation)
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
              let chips = tab.digArray(
                  JSONKey.content,
                  "richGridRenderer",
                  "header",
                  "feedFilterChipBarRenderer",
                  JSONKey.contents
              )
        else { return [] }
        return chips.compactMap { item -> ChannelFilterChip? in
            guard let chip = item["chipCloudChipRenderer"] as? [String: Any],
                  let label = chip.digString("text", "simpleText"),
                  let params = chip.digString(
                      "navigationEndpoint", "browseEndpoint", JSONKey.params
                  )
            else { return nil }
            return ChannelFilterChip(label: label, params: params)
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
