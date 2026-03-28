import Foundation

extension InnertubeClient {
    static func parseC4ChannelHeader(
        _ json: [String: Any],
        fallbackId: String
    ) -> ChannelInfo? {
        let c4 = firstRenderer(
            in: json,
            named: "c4TabbedHeaderRenderer"
        )
        let ch = firstRenderer(
            in: json,
            named: "channelHeaderRenderer"
        )
        guard c4 != nil || ch != nil
        else {
            return nil
        }
        var fields = ChannelFields(
            id: c4ChannelId(
                c4: c4, ch: ch, fallback: fallbackId
            ),
            title: c4Title(c4: c4, ch: ch),
            avatarURL: c4Avatar(c4: c4, ch: ch)
        )
        fields.bannerURL = c4Banner(c4)
        fields.isVerified = c4IsVerified(c4)
        fields.subscriberCountText = c4SubCount(
            c4: c4, ch: ch
        )
        return buildChannelInfo(fields)
    }

    static func parseLockupChannel(
        _ json: [String: Any],
        fallbackId: String
    ) -> ChannelInfo? {
        guard let lockup = firstRenderer(
            in: json, named: "avatarLockupRenderer"
        )
        else {
            return nil
        }
        let avatarURL = extractThumbnailURL(
            from: lockup["avatar"]
        ) ?? extractThumbnailURL(from: lockup["thumbnail"])
        let title = simpleText(from: lockup["title"])
            ?? simpleText(from: lockup["text"]) ?? ""
        let subCount = simpleText(
            from: lockup["subtitle"]
        ) ?? simpleText(from: lockup["accessibilityText"])
        let channelId = firstMatchingBrowseId(in: lockup) ?? fallbackId
        var fields = ChannelFields(
            id: channelId, title: title, avatarURL: avatarURL
        )
        fields.subscriberCountText = subCount
        return buildChannelInfo(fields)
    }

    static func parseMetadataChannel(
        _ json: [String: Any],
        fallbackId: String
    ) -> ChannelInfo? {
        guard let meta = firstRenderer(
            in: json, named: "channelMetadataRenderer"
        )
        else {
            return nil
        }
        let avatarDict = meta["avatar"] as? [String: Any]
        let thumbs = avatarDict?["thumbnails"] as? [[String: Any]]
        let avatarURL = thumbs?.last?["url"] as? String
        let title = meta["title"] as? String ?? ""
        let channelId = meta["externalId"] as? String ?? fallbackId
        return buildChannelInfo(ChannelFields(
            id: channelId, title: title, avatarURL: avatarURL
        ))
    }

    static func parseHeuristicChannel(
        _ json: [String: Any],
        fallbackId: String
    ) -> ChannelInfo? {
        guard let header = findChannelHeaderCandidate(in: json)
        else {
            return nil
        }
        let avatarURL = heuristicAvatar(header)
        let title = header["title"] as? String
            ?? simpleText(from: header["title"])
            ?? simpleText(from: header["pageTitle"]) ?? ""
        let subCount = heuristicSubCount(header)
        let channelId = header["channelId"] as? String ?? fallbackId
        var fields = ChannelFields(
            id: channelId, title: title, avatarURL: avatarURL
        )
        fields.subscriberCountText = subCount
        return buildChannelInfo(fields)
    }

    static func logChannelFailure(
        _ json: [String: Any],
        channelId: String
    ) {
        let contents = json["contents"]
            as? [String: Any]
        if let tvBrowse = contents?[
            "tvBrowseRenderer"
        ] as? [String: Any] {
            logTvBrowseFailure(
                tvBrowse, channelId: channelId
            )
        } else {
            let topKeys = sortedKeys(json)
            AppLog.innertube(
                "parseChannelInfo failed for"
                    + " \(channelId)."
                    + " top-level keys: \(topKeys)"
            )
        }
    }
}

private extension InnertubeClient {
    static func c4Title(
        c4: [String: Any]?,
        ch: [String: Any]?
    ) -> String {
        if let c4 {
            if let title = c4["title"] as? String,
               !title.isEmpty {
                return title
            }
            if let title = simpleText(
                from: c4["title"]
            ), !title.isEmpty {
                return title
            }
        }
        if let ch {
            return simpleText(from: ch["title"])
                ?? ch["title"] as? String
                ?? simpleText(from: ch["headline"])
                ?? ""
        }
        return ""
    }

    static func c4Avatar(
        c4: [String: Any]?,
        ch: [String: Any]?
    ) -> String? {
        if let c4 {
            let thumbs = (c4["avatar"]
                as? [String: Any])?["thumbnails"]
                as? [[String: Any]]
            if let url = thumbs?.last?["url"]
                as? String {
                return url
            }
        }
        if let ch {
            return extractThumbnailURL(
                from: ch["avatar"]
            ) ?? extractThumbnailURL(
                from: ch["thumbnail"]
            ) ?? extractThumbnailURL(
                from: ch["image"]
            )
        }
        return nil
    }

    static func c4SubCount(
        c4: [String: Any]?,
        ch: [String: Any]?
    ) -> String? {
        if let c4,
           let text = simpleText(
            from: c4["subscriberCountText"]
           ) {
            return text
        }
        if let ch {
            return simpleText(
                from: ch["subscriberCountText"]
            ) ?? simpleText(from: ch["metadata"])
                ?? simpleText(from: ch["subtitle"])
        }
        return nil
    }

    static func c4Banner(
        _ c4: [String: Any]?
    ) -> String? {
        let banner = c4?["banner"] as? [String: Any]
        return (banner?["thumbnails"]
            as? [[String: Any]])?
            .last?["url"] as? String
    }

    static func c4IsVerified(
        _ c4: [String: Any]?
    ) -> Bool {
        let badges = c4?["badges"]
            as? [[String: Any]] ?? []
        return badges.contains { badge in
            guard let renderer = badge[
                "metadataBadgeRenderer"
            ] as? [String: Any]
            else {
                return false
            }
            let style = renderer["style"]
                as? String ?? ""
            let iconType = (renderer["icon"]
                as? [String: Any])?["iconType"]
                as? String ?? ""
            return style
                == "BADGE_STYLE_TYPE_VERIFIED"
                || iconType == "CHECK_CIRCLE_THICK"
                || iconType == "OFFICIAL_ARTIST_BADGE"
        }
    }

    static func c4ChannelId(
        c4: [String: Any]?,
        ch: [String: Any]?,
        fallback: String
    ) -> String {
        c4?["channelId"] as? String
            ?? ch?["channelId"] as? String
            ?? fallback
    }

    static func heuristicAvatar(
        _ header: [String: Any]
    ) -> String? {
        let avatar = header["avatar"] as? [String: Any]
        let boxArt = header["boxArt"] as? [String: Any]
        let avatarThumb = (avatar?["thumbnails"]
            as? [[String: Any]])?
            .last?["url"] as? String
        let boxThumb = (boxArt?["thumbnails"]
            as? [[String: Any]])?
            .last?["url"] as? String
        return avatarThumb ?? boxThumb
    }

    static func heuristicSubCount(
        _ header: [String: Any]
    ) -> String? {
        simpleText(
            from: header["subscriberCountText"]
        ) ?? simpleText(from: header["metadata"])
            ?? simpleText(from: header["description"])
    }

    static func sortedKeys(
        _ dict: [String: Any]?
    ) -> String {
        dict?.keys
            .sorted()
            .joined(separator: ", ") ?? "nil"
    }

    static func logTvBrowseFailure(
        _ tvBrowse: [String: Any],
        channelId: String
    ) {
        let topKeys = sortedKeys(tvBrowse)
        let hKeys = sortedKeys(tvBrowse["header"] as? [String: Any])
        let cKeys = sortedKeys(tvBrowse["content"] as? [String: Any])
        let renderers = Array(collectRendererKeys(in: tvBrowse).prefix(30))
            .sorted()
            .joined(separator: ", ")
        let thumbURLs = Array(collectThumbnailURLs(in: tvBrowse).prefix(10))
            .joined(separator: ", ")
        AppLog.innertube(
            "parseChannelInfo failed for \(channelId)."
                + " tvBrowse keys: \(topKeys)."
                + " header keys: \(hKeys)."
                + " content keys: \(cKeys)"
        )
        AppLog.innertube(
            "channel renderers for \(channelId)"
                + ": \(renderers)"
        )
        AppLog.innertube(
            "channel thumbnails for \(channelId)"
                + ": \(thumbURLs)"
        )
    }
}
