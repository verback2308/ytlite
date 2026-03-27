import Foundation

extension InnertubeClient {

    // MARK: - Web client browse parsing (FEhistory, etc.)

    /// TV-client history page. TV browses FEhistory and returns sections of videos.
    static func parseTVHistoryPage(_ json: [String: Any]) -> FeedPage {
        var videos: [Video] = []
        var continuation: String?

        // Continuation response — TV gridContinuation (history pagination)
        if let cc = json["continuationContents"] as? [String: Any] {
            if let gc = cc["gridContinuation"] as? [String: Any],
               let items = gc["items"] as? [[String: Any]] {
                let vids = VideoRendererParserChain.videos(from: items)
                let cont = (gc["continuations"] as? [[String: Any]])?
                    .first.flatMap { ($0["nextContinuationData"] as? [String: Any])?["continuation"] as? String }
                AppLog.innertube("TV history gridContinuation: \(vids.count) more videos")
                return FeedPage(videos: vids, continuation: cont)
            }
            // Fallback: sectionListContinuation
            if let slr = cc["sectionListContinuation"] as? [String: Any] {
                return parseSectionList(slr)
            }
        }

        // TV FEhistory structure:
        // contents.tvBrowseRenderer.content.tvSurfaceContentRenderer.content.gridRenderer.items[]
        if let tvBrowse = (json[JSONKey.contents] as? [String: Any])?[RendererKey.tvBrowse] as? [String: Any],
           let tvContent = tvBrowse[JSONKey.content] as? [String: Any],
           let tvSurface = tvContent[RendererKey.tvSurfaceContent] as? [String: Any],
           let innerContent = tvSurface[JSONKey.content] as? [String: Any],
           let grid = innerContent[RendererKey.grid] as? [String: Any],
           let items = grid[JSONKey.items] as? [[String: Any]] {
            let videos = VideoRendererParserChain.videos(from: items)
            let cont = (grid["continuations"] as? [[String: Any]])?
                .first.flatMap { ($0["nextContinuationData"] as? [String: Any])?["continuation"] as? String }
            AppLog.innertube("TV history gridRenderer: \(videos.count) videos")
            return FeedPage(videos: videos, continuation: cont)
        }


        // Path 1: tvBrowseRenderer (same as home/subscriptions)
        if let slr = extractSectionList(from: json) {
            return parseSectionList(slr)
        }

        // Path 2: twoColumnBrowseResultsRenderer (web-style even in TV response)
        let contents = json[JSONKey.contents] as? [String: Any]
        if let tcbr = contents?[RendererKey.twoColumnBrowse] as? [String: Any] {
            let tabList = tcbr[JSONKey.tabs] as? [[String: Any]] ?? []
            for tab in tabList {
                guard let tabRenderer = tab[RendererKey.tab] as? [String: Any],
                      let content = tabRenderer[JSONKey.content] as? [String: Any],
                      let slr = content[RendererKey.sectionList] as? [String: Any]
                else { continue }
                let page = parseWebSectionList(slr)
                videos.append(contentsOf: page.videos)
                if continuation == nil { continuation = page.continuation }
            }
            if !videos.isEmpty { return FeedPage(videos: videos, continuation: continuation) }
        }

        // Path 3: sectionListRenderer directly under contents
        if let slr = contents?[RendererKey.sectionList] as? [String: Any] {
            let page = parseWebSectionList(slr)
            if !page.videos.isEmpty { return page }
        }

        // Path 4: richGridRenderer
        if let richGrid = contents?[RendererKey.richGrid] as? [String: Any],
           let items = richGrid[JSONKey.contents] as? [[String: Any]] {
            let (parsed, cont) = VideoRendererParserChain.parse(items: items)
            videos.append(contentsOf: parsed)
            if cont != nil { continuation = cont }
            if !videos.isEmpty { return FeedPage(videos: videos, continuation: continuation) }
        }

        // Log unknown structure
        AppLog.innertube("parseTVHistoryPage: unknown structure. topKeys=\(json.keys.sorted())")
        if let c = contents { AppLog.innertube("contentsKeys=\(c.keys.sorted())") }
        return FeedPage(videos: [], continuation: nil)
    }



    /// Parses a web-client browse response (twoColumnBrowseResultsRenderer).
    /// History structure: contents → twoColumnBrowseResultsRenderer → tabs[0] → tabRenderer →
    ///   content → sectionListRenderer → contents[] → itemSectionRenderer → contents[] → videoRenderer
    static func parseWebBrowsePage(_ json: [String: Any]) -> FeedPage {
        var videos: [Video] = []
        var continuation: String?

        if let cc = json["continuationContents"] as? [String: Any] {
            if let slr = cc["sectionListContinuation"] as? [String: Any] {
                return parseWebSectionList(slr)
            }
            if let rgc = cc["richGridContinuation"] as? [String: Any] {
                let items = rgc[JSONKey.contents] as? [[String: Any]] ?? []
                let (videos, cont) = VideoRendererParserChain.parse(items: items)
                return FeedPage(videos: videos, continuation: cont)
            }
        }

        let tabs = json.digDict(JSONKey.contents, RendererKey.twoColumnBrowse)
        let tabList = tabs?[JSONKey.tabs] as? [[String: Any]] ?? []
        for tab in tabList {
            guard let slr = tab.digDict(RendererKey.tab, JSONKey.content, RendererKey.sectionList)
            else { continue }
            let page = parseWebSectionList(slr)
            videos.append(contentsOf: page.videos)
            if continuation == nil { continuation = page.continuation }
        }

        if videos.isEmpty,
           let richGrid = json.digDict(JSONKey.contents, RendererKey.richGrid),
           let contents = richGrid[JSONKey.contents] as? [[String: Any]] {
            let (parsed, cont) = VideoRendererParserChain.parse(items: contents)
            videos.append(contentsOf: parsed)
            if cont != nil { continuation = cont }
        }

        return FeedPage(videos: videos, continuation: continuation)
    }

    static func parseWebSectionList(_ slr: [String: Any]) -> FeedPage {
        let sections = slr[JSONKey.contents] as? [[String: Any]] ?? []
        var videos: [Video] = []
        var continuation: String?

        for section in sections {
            if let isr = section[RendererKey.itemSection] as? [String: Any],
               let contents = isr[JSONKey.contents] as? [[String: Any]] {
                videos.append(contentsOf: VideoRendererParserChain.videos(from: contents))
            }
            if let shelf = section[RendererKey.shelf] as? [String: Any],
               let content = shelf[JSONKey.content] as? [String: Any] {
                for listKey in [RendererKey.verticalList, RendererKey.horizontalList] {
                    if let items = (content[listKey] as? [String: Any])?[JSONKey.items] as? [[String: Any]] {
                        videos.append(contentsOf: VideoRendererParserChain.videos(from: items))
                    }
                }
                if let items = content[JSONKey.contents] as? [[String: Any]] {
                    videos.append(contentsOf: VideoRendererParserChain.videos(from: items))
                }
            }
            if let ct = section[RendererKey.continuationItem] as? [String: Any],
               let token = ct.digString("continuationEndpoint", "continuationCommand", JSONKey.token) {
                continuation = token
            }
        }

        return FeedPage(videos: videos, continuation: continuation)
    }

    /// Parse a web-client videoRenderer into a Video model.
    static func parseWebVideoRenderer(_ vr: [String: Any]) -> Video? {
        guard let videoId = vr[JSONKey.videoId] as? String else { return nil }

        let title = simpleText(from: vr[JSONKey.title]) ?? ""
        guard !title.isEmpty else { return nil }

        let rawThumbURL = vr.thumbnailURL() ?? ""
        let thumbURL = preferredThumbnailURL(videoId: videoId, fallbackURL: rawThumbURL)

        let channelName = vr.digString("ownerText", JSONKey.runs, 0, JSONKey.text) ?? ""
        let channelId = vr.digString("ownerText", JSONKey.runs, 0, "navigationEndpoint", "browseEndpoint", JSONKey.browseId)

        let viewCount = simpleText(from: vr["viewCountText"])
        let publishedAt = simpleText(from: vr["publishedTimeText"])

        let overlays = vr["thumbnailOverlays"] as? [[String: Any]] ?? []
        let isLive = overlays.contains {
            ($0[RendererKey.thumbnailOverlayTimeStatus] as? [String: Any])?["style"] as? String == "LIVE"
        }
        let duration: String? = isLive ? nil :
            simpleText(from: vr["lengthText"])
            ?? vr.digString("lengthText", "accessibility", "accessibilityData", "label")

        logThumbnailChoice(videoId: videoId, chosenURL: thumbURL, fallbackURL: rawThumbURL)
        return Video(id: videoId, title: title, channelId: channelId,
                     channelName: channelName, channelAvatarURL: nil,
                     thumbnailURL: thumbURL, viewCount: viewCount,
                     publishedAt: publishedAt, duration: duration, isLive: isLive)
    }

    static func parseWatchMetadata(_ json: [String: Any]) -> (title: String?, viewCountText: String?, publishedText: String?) {
        if let renderer = firstRenderer(in: json, named: "slimVideoMetadataRenderer") {
            let title = simpleText(from: renderer["title"])
            let lines = renderer["lines"] as? [[String: Any]] ?? []
            var parts: [String] = []

            for line in lines {
                let items = (line["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
                for item in items {
                    if let text = simpleText(from: (item["lineItemRenderer"] as? [String: Any])?["text"]),
                       !text.isEmpty,
                       text != "•" {
                        parts.append(text)
                    }
                }
            }

            return (title, parts.first, parts.dropFirst().first)
        }

        if let renderer = firstRenderer(in: json, named: "videoMetadataRenderer") {
            let title = simpleText(from: renderer["title"])
            let viewCountText = simpleText(from: renderer["viewCountText"])
            let publishedText = simpleText(from: renderer["dateText"])
            return (title, viewCountText, publishedText)
        }

        return (nil, nil, nil)
    }

    static func parseWatchDescription(_ json: [String: Any]) -> String? {
        if let renderer = firstRenderer(in: json, named: "expandableVideoDescriptionBodyRenderer") {
            return simpleText(from: renderer["descriptionBodyText"]) ?? simpleText(from: renderer["showMoreText"])
        }

        if let renderer = firstRenderer(in: json, named: "videoMetadataRenderer") {
            return simpleText(from: renderer["description"])
        }

        return nil
    }

    static func parseWatchChannelInfo(_ json: [String: Any], fallbackVideo: Video) -> ChannelInfo? {
        if let lockup = firstRenderer(in: json, named: "avatarLockupRenderer") {
            let avatarURL = extractThumbnailURL(from: lockup["avatar"]) ??
                extractThumbnailURL(from: lockup["thumbnail"])
            let title = simpleText(from: lockup["title"]) ?? fallbackVideo.channelName
            let subtitle = simpleText(from: lockup["subtitle"])
            let channelId = firstMatchingBrowseId(in: lockup) ?? fallbackVideo.channelId ?? ""

            if !title.isEmpty || avatarURL != nil {
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subtitle,
                                   bannerURL: nil, isVerified: false,
                                   description: nil, contactInfo: nil, videoCountText: nil)
            }
        }

        if let fallbackId = fallbackVideo.channelId {
            return ChannelInfo(id: fallbackId,
                               title: fallbackVideo.channelName,
                               avatarURL: fallbackVideo.channelAvatarURL,
                               subscriberCountText: nil,
                               bannerURL: nil, isVerified: false,
                               description: nil, contactInfo: nil, videoCountText: nil)
        }

        return nil
    }

    static func parseTileRenderer(_ tile: [String: Any]) -> Video? {
        guard let videoId = tile.digString("onSelectCommand", "watchEndpoint", JSONKey.videoId)
        else { return nil }

        let meta = tile.digDict("metadata", RendererKey.tileMetadata)
        let title = simpleText(from: meta?[JSONKey.title]) ?? ""

        let lines = meta?["lines"] as? [[String: Any]] ?? []
        let firstLineItems = (lines.first?[RendererKey.line] as? [String: Any])?[JSONKey.items] as? [[String: Any]] ?? []
        let channel = firstLineItems.first.flatMap { li in
            simpleText(from: (li[RendererKey.lineItem] as? [String: Any])?[JSONKey.text])
        } ?? ""
        let channelId = extractChannelId(from: tile, firstLineItems: firstLineItems)
        let channelAvatarURL = extractChannelAvatarURL(from: tile)

        let tileHeader = tile.digDict(JSONKey.header, RendererKey.tileHeader)
        let rawThumbURL = tileHeader?.thumbnailURL() ?? ""
        let thumbURL = preferredThumbnailURL(videoId: videoId, fallbackURL: rawThumbURL)

        let overlays = tileHeader?["thumbnailOverlays"] as? [[String: Any]] ?? []
        let isLive = overlays.contains {
            ($0[RendererKey.thumbnailOverlayTimeStatus] as? [String: Any])?["style"] as? String == "LIVE"
        }
        let duration = isLive ? nil : overlays.compactMap { overlay -> String? in
            simpleText(from: (overlay[RendererKey.thumbnailOverlayTimeStatus] as? [String: Any])?[JSONKey.text])
        }.first

        var viewCount: String? = nil
        var publishedAt: String? = nil
        if lines.count > 1 {
            let items = (lines[1][RendererKey.line] as? [String: Any])?[JSONKey.items] as? [[String: Any]] ?? []
            for li in items {
                let text = simpleText(from: (li[RendererKey.lineItem] as? [String: Any])?[JSONKey.text]) ?? ""
                if text == "•" || text == "·" || text.isEmpty { continue }
                if text.contains("view") || text.contains("просмотр")
                    || text.contains("watching") || text.contains("смотр") {
                    viewCount = text
                } else if text.contains("ago") || text.contains("назад") || text.contains("hour")
                       || text.contains("day") || text.contains("week") || text.contains("month")
                       || text.contains("year") || text.contains("час") || text.contains("нед")
                       || text.contains("мес") || text.contains("лет") || text.contains("дн")
                       || text.contains("мин") || text.contains("сек") {
                    publishedAt = text
                }
            }
        }

        logThumbnailChoice(videoId: videoId, chosenURL: thumbURL, fallbackURL: rawThumbURL)
        return Video(id: videoId, title: title, channelId: channelId,
                     channelName: channel, channelAvatarURL: channelAvatarURL,
                     thumbnailURL: thumbURL, viewCount: viewCount,
                     publishedAt: publishedAt, duration: duration, isLive: isLive)
    }

    /// Parse a radioRenderer (YouTube Mix / autoplay queue) into a Video.
    static func parseRadioRenderer(_ rr: [String: Any]) -> Video? {
        guard let videoId = rr["videoId"] as? String else { return nil }
        let title = simpleText(from: rr["title"]) ?? "YouTube Mix"
        let thumbs = (rr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let thumbURL = thumbs.last?["url"] as? String
            ?? AppURLs.YouTube.thumbnailURL(videoId: videoId)
        let videoCount = (rr["videoCountText"] as? [String: Any]).flatMap { obj -> String? in
            if let simple = obj["simpleText"] as? String { return simple }
            return (obj["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        }
        return Video(id: videoId, title: title, channelId: nil,
                     channelName: "YouTube Mix", channelAvatarURL: nil,
                     thumbnailURL: thumbURL, viewCount: videoCount,
                     publishedAt: nil, duration: "Mix", isLive: false)
    }

    /// Parse a playlistRenderer into a Video using its first video as the entry point.
    static func parsePlaylistRenderer(_ pr: [String: Any]) -> Video? {
        // Need a videoId to play — use firstVideoId from the renderer if available
        let firstVideoId = pr["firstVideoId"] as? String
            ?? (pr["navigationEndpoint"] as? [String: Any]).flatMap {
                ($0["watchEndpoint"] as? [String: Any])?["videoId"] as? String
            }
            ?? (pr["videos"] as? [[String: Any]])?.first.flatMap {
                ($0["childVideoRenderer"] as? [String: Any])?["videoId"] as? String
            }
        guard let videoId = firstVideoId else { return nil }
        let title = simpleText(from: pr["title"]) ?? "Playlist"
        let thumbs = (pr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let thumbURL = thumbs.last?["url"] as? String
            ?? AppURLs.YouTube.thumbnailURL(videoId: videoId)
        let videoCount = pr["videoCount"] as? String
        return Video(id: videoId, title: title, channelId: nil,
                     channelName: "Playlist", channelAvatarURL: nil,
                     thumbnailURL: thumbURL, viewCount: videoCount.map { "\($0) videos" },
                     publishedAt: nil, duration: nil, isLive: false)
    }

}
