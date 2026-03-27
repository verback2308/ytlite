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
                var vids: [Video] = []
                for item in items {
                    if let tile = item["tileRenderer"] as? [String: Any],
                       let v = parseTileRenderer(tile) { vids.append(v) }
                    if let vr = item["videoRenderer"] as? [String: Any],
                       let v = parseWebVideoRenderer(vr) { vids.append(v) }
                    if let vr = item["compactVideoRenderer"] as? [String: Any],
                       let v = parseWebVideoRenderer(vr) { vids.append(v) }
                }
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
        if let tvBrowse = (json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any],
           let tvContent = tvBrowse["content"] as? [String: Any],
           let tvSurface = tvContent["tvSurfaceContentRenderer"] as? [String: Any],
           let innerContent = tvSurface["content"] as? [String: Any],
           let grid = innerContent["gridRenderer"] as? [String: Any],
           let items = grid["items"] as? [[String: Any]] {
            var videos: [Video] = []
            for item in items {
                if let tile = item["tileRenderer"] as? [String: Any],
                   let video = parseTileRenderer(tile) { videos.append(video) }
                // gridRenderer may also have videoRenderer items
                if let vr = item["videoRenderer"] as? [String: Any],
                   let video = parseWebVideoRenderer(vr) { videos.append(video) }
                if let vr = item["compactVideoRenderer"] as? [String: Any],
                   let video = parseWebVideoRenderer(vr) { videos.append(video) }
            }
            // Continuation from gridRenderer.continuations
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
        let contents = json["contents"] as? [String: Any]
        if let tcbr = contents?["twoColumnBrowseResultsRenderer"] as? [String: Any] {
            let tabList = tcbr["tabs"] as? [[String: Any]] ?? []
            for tab in tabList {
                guard let tabRenderer = tab["tabRenderer"] as? [String: Any],
                      let content = tabRenderer["content"] as? [String: Any],
                      let slr = content["sectionListRenderer"] as? [String: Any]
                else { continue }
                let page = parseWebSectionList(slr)
                videos.append(contentsOf: page.videos)
                if continuation == nil { continuation = page.continuation }
            }
            if !videos.isEmpty { return FeedPage(videos: videos, continuation: continuation) }
        }

        // Path 3: sectionListRenderer directly under contents
        if let slr = contents?["sectionListRenderer"] as? [String: Any] {
            let page = parseWebSectionList(slr)
            if !page.videos.isEmpty { return page }
        }

        // Path 4: richGridRenderer
        if let richGrid = contents?["richGridRenderer"] as? [String: Any],
           let items = richGrid["contents"] as? [[String: Any]] {
            for item in items {
                if let richItem = (item["richItemRenderer"] as? [String: Any])?["content"] as? [String: Any] {
                    if let vr = richItem["videoRenderer"] as? [String: Any],
                       let video = parseWebVideoRenderer(vr) { videos.append(video) }
                    if let rr = richItem["radioRenderer"] as? [String: Any],
                       let video = parseRadioRenderer(rr) { videos.append(video) }
                    if let pr = richItem["playlistRenderer"] as? [String: Any],
                       let video = parsePlaylistRenderer(pr) { videos.append(video) }
                }
                if let ct = (item["continuationItemRenderer"] as? [String: Any])?["continuationEndpoint"] as? [String: Any],
                   let token = (ct["continuationCommand"] as? [String: Any])?["token"] as? String {
                    continuation = token
                }
            }
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

        // Continuation response
        if let cc = json["continuationContents"] as? [String: Any],
           let slr = cc["sectionListContinuation"] as? [String: Any] {
            return parseWebSectionList(slr)
        }

        // Initial response via twoColumnBrowseResultsRenderer
        let tabs = (json["contents"] as? [String: Any])?["twoColumnBrowseResultsRenderer"] as? [String: Any]
        let tabList = tabs?["tabs"] as? [[String: Any]] ?? []
        for tab in tabList {
            guard let tabRenderer = tab["tabRenderer"] as? [String: Any],
                  let content = tabRenderer["content"] as? [String: Any],
                  let slr = content["sectionListRenderer"] as? [String: Any]
            else { continue }
            let page = parseWebSectionList(slr)
            videos.append(contentsOf: page.videos)
            if continuation == nil { continuation = page.continuation }
        }

        // Fallback: richGridRenderer (used by some web browse endpoints)
        if videos.isEmpty,
           let richGrid = (json["contents"] as? [String: Any])?["richGridRenderer"] as? [String: Any],
           let contents = richGrid["contents"] as? [[String: Any]] {
            for item in contents {
                if let richItem = (item["richItemRenderer"] as? [String: Any])?["content"] as? [String: Any] {
                    if let vr = richItem["videoRenderer"] as? [String: Any],
                       let video = parseWebVideoRenderer(vr) { videos.append(video) }
                    if let rr = richItem["radioRenderer"] as? [String: Any],
                       let video = parseRadioRenderer(rr) { videos.append(video) }
                    if let pr = richItem["playlistRenderer"] as? [String: Any],
                       let video = parsePlaylistRenderer(pr) { videos.append(video) }
                }
                if let ct = (item["continuationItemRenderer"] as? [String: Any])?["continuationEndpoint"] as? [String: Any],
                   let token = (ct["continuationCommand"] as? [String: Any])?["token"] as? String {
                    continuation = token
                }
            }
        }

        return FeedPage(videos: videos, continuation: continuation)
    }

    static func parseWebSectionList(_ slr: [String: Any]) -> FeedPage {
        let sections = slr["contents"] as? [[String: Any]] ?? []
        var videos: [Video] = []
        var continuation: String?

        for section in sections {
            // itemSectionRenderer — groups of videos (e.g. "Today", "Yesterday")
            if let isr = section["itemSectionRenderer"] as? [String: Any],
               let contents = isr["contents"] as? [[String: Any]] {
                for item in contents {
                    if let vr = item["videoRenderer"] as? [String: Any],
                       let video = parseWebVideoRenderer(vr) {
                        videos.append(video)
                    }
                    // compactVideoRenderer (sometimes used)
                    if let cvr = item["compactVideoRenderer"] as? [String: Any],
                       let video = parseWebVideoRenderer(cvr) {
                        videos.append(video)
                    }
                    if let rr = item["radioRenderer"] as? [String: Any],
                       let video = parseRadioRenderer(rr) {
                        videos.append(video)
                    }
                    if let pr = item["playlistRenderer"] as? [String: Any],
                       let video = parsePlaylistRenderer(pr) {
                        videos.append(video)
                    }
                }
            }
            // shelfRenderer — also used by history (sections titled "Today", "This week", etc.)
            if let shelf = section["shelfRenderer"] as? [String: Any],
               let content = shelf["content"] as? [String: Any] {
                // Vertical list
                if let vertList = content["verticalListRenderer"] as? [String: Any],
                   let items = vertList["items"] as? [[String: Any]] {
                    for item in items {
                        if let vr = item["videoRenderer"] as? [String: Any],
                           let video = parseWebVideoRenderer(vr) { videos.append(video) }
                        if let cvr = item["compactVideoRenderer"] as? [String: Any],
                           let video = parseWebVideoRenderer(cvr) { videos.append(video) }
                        if let rr = item["radioRenderer"] as? [String: Any],
                           let video = parseRadioRenderer(rr) { videos.append(video) }
                        if let pr = item["playlistRenderer"] as? [String: Any],
                           let video = parsePlaylistRenderer(pr) { videos.append(video) }
                    }
                }
                // Horizontal list
                if let horizList = content["horizontalListRenderer"] as? [String: Any],
                   let items = horizList["items"] as? [[String: Any]] {
                    for item in items {
                        if let vr = item["videoRenderer"] as? [String: Any],
                           let video = parseWebVideoRenderer(vr) { videos.append(video) }
                        if let tile = item["tileRenderer"] as? [String: Any],
                           let video = parseTileRenderer(tile) { videos.append(video) }
                        if let rr = item["radioRenderer"] as? [String: Any],
                           let video = parseRadioRenderer(rr) { videos.append(video) }
                        if let pr = item["playlistRenderer"] as? [String: Any],
                           let video = parsePlaylistRenderer(pr) { videos.append(video) }
                    }
                }
                // Expanded shelf with contents directly
                if let items = content["contents"] as? [[String: Any]] {
                    for item in items {
                        if let vr = item["videoRenderer"] as? [String: Any],
                           let video = parseWebVideoRenderer(vr) { videos.append(video) }
                        if let rr = item["radioRenderer"] as? [String: Any],
                           let video = parseRadioRenderer(rr) { videos.append(video) }
                        if let pr = item["playlistRenderer"] as? [String: Any],
                           let video = parsePlaylistRenderer(pr) { videos.append(video) }
                    }
                }
            }
            // Continuation token
            if let ct = section["continuationItemRenderer"] as? [String: Any],
               let ep = ct["continuationEndpoint"] as? [String: Any],
               let token = (ep["continuationCommand"] as? [String: Any])?["token"] as? String {
                continuation = token
            }
        }

        return FeedPage(videos: videos, continuation: continuation)
    }

    /// Parse a web-client videoRenderer into a Video model.
    static func parseWebVideoRenderer(_ vr: [String: Any]) -> Video? {
        guard let videoId = vr["videoId"] as? String else { return nil }

        let title = simpleText(from: vr["title"])
            ?? ((vr["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined()

        guard let title = title, !title.isEmpty else { return nil }

        // Thumbnail — pick highest quality
        let thumbs = (vr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let thumbURL = thumbs.last?["url"] as? String
            ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"

        // Channel info
        let channelName: String
        let channelId: String?
        if let ownerText = vr["ownerText"] as? [String: Any],
           let runs = ownerText["runs"] as? [[String: Any]],
           let first = runs.first {
            channelName = first["text"] as? String ?? ""
            let nav = first["navigationEndpoint"] as? [String: Any]
            let browse = nav?["browseEndpoint"] as? [String: Any]
            channelId = browse?["browseId"] as? String
        } else {
            channelName = ""
            channelId = nil
        }

        // View count
        let viewCount: String?
        if let vcObj = vr["viewCountText"] as? [String: Any] {
            viewCount = vcObj["simpleText"] as? String
                ?? (vcObj["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
        } else {
            viewCount = nil
        }

        // Published date
        let publishedAt = simpleText(from: vr["publishedTimeText"])

        // Duration + isLive
        let duration: String?
        var isLive = false
        let overlays = vr["thumbnailOverlays"] as? [[String: Any]] ?? []
        if overlays.contains(where: { ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "LIVE" }) {
            duration = nil
            isLive = true
        } else if let d = simpleText(from: vr["lengthText"]) {
            duration = d
        } else if let acc = (vr["lengthText"] as? [String: Any])?["accessibility"] as? [String: Any],
                  let data = acc["accessibilityData"] as? [String: Any] {
            duration = data["label"] as? String
        } else {
            duration = nil
        }

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
        guard let videoId = ((tile["onSelectCommand"] as? [String: Any])?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
        else { return nil }

        let meta = (tile["metadata"] as? [String: Any])?["tileMetadataRenderer"] as? [String: Any]
        let title = (meta?["title"] as? [String: Any])?["simpleText"] as? String ?? ""

        let lines = meta?["lines"] as? [[String: Any]] ?? []
        let firstLineItems = (lines.first?["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        let channel = ((firstLineItems.first?["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any])
            .flatMap { ($0["runs"] as? [[String: Any]])?.first?["text"] as? String } ?? ""
        let channelId = extractChannelId(from: tile, firstLineItems: firstLineItems)
        let channelAvatarURL = extractChannelAvatarURL(from: tile)

        let tileHeader = (tile["header"] as? [String: Any])?["tileHeaderRenderer"] as? [String: Any]
        let thumbs = (tileHeader?["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
        let rawThumbURL = thumbs.last?["url"] as? String ?? ""
        let thumbURL = preferredThumbnailURL(videoId: videoId, fallbackURL: rawThumbURL)

        let overlays = tileHeader?["thumbnailOverlays"] as? [[String: Any]] ?? []
        let isLive = overlays.contains {
            ($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["style"] as? String == "LIVE"
        }
        let duration = isLive ? nil : overlays.compactMap {
            ((($0["thumbnailOverlayTimeStatusRenderer"] as? [String: Any])?["text"] as? [String: Any])?["simpleText"] as? String)
        }.first

        var viewCount: String? = nil
        var publishedAt: String? = nil
        if lines.count > 1 {
            let items = (lines[1]["lineRenderer"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
            for li in items {
                let textObj = (li["lineItemRenderer"] as? [String: Any])?["text"] as? [String: Any]
                // Support both simpleText and runs formats
                let text = textObj?["simpleText"] as? String
                    ?? (textObj?["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
                    ?? ""
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
            ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
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
            ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        let videoCount = pr["videoCount"] as? String
        return Video(id: videoId, title: title, channelId: nil,
                     channelName: "Playlist", channelAvatarURL: nil,
                     thumbnailURL: thumbURL, viewCount: videoCount.map { "\($0) videos" },
                     publishedAt: nil, duration: nil, isLive: false)
    }

}
