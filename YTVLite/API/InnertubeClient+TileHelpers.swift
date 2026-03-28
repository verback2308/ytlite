import Foundation

// MARK: - Tile Helpers
extension InnertubeClient {
    static func buildTileVideo(
        videoId: String,
        title: String,
        tile: [String: Any],
        meta: [String: Any]?
    ) -> Video {
        let lines = meta?["lines"] as? [[String: Any]] ?? []
        let channel = extractTileChannel(from: lines)
        let chId = extractChannelId(from: tile, firstLineItems: channel.items)
        let chAvatar = extractChannelAvatarURL(from: tile)
        let thumbInfo = resolveTileThumb(videoId: videoId, tile: tile)
        let overlay = parseTileOverlay(tile: tile)
        let timing = parseTileTiming(lines: lines)
        logThumbnailChoice(
            videoId: videoId,
            chosenURL: thumbInfo.url,
            fallbackURL: thumbInfo.raw
        )
        return Video(
            id: videoId,
            title: title,
            channelId: chId,
            channelName: channel.name,
            channelAvatarURL: chAvatar,
            thumbnailURL: thumbInfo.url,
            viewCount: timing.viewCount,
            publishedAt: timing.publishedAt,
            duration: overlay.duration,
            isLive: overlay.isLive
        )
    }

    static func checkOverlayLive(
        _ overlaysAny: Any?
    ) -> Bool {
        let overlays = overlaysAny
            as? [[String: Any]] ?? []
        let key = RendererKey
            .thumbnailOverlayTimeStatus
        return overlays.contains {
            ($0[key] as? [String: Any])?["style"]
                as? String == "LIVE"
        }
    }
}

// MARK: - Private Tile Helpers
private extension InnertubeClient {
    static func extractTileChannel(
        from lines: [[String: Any]]
    ) -> (name: String, items: [[String: Any]]) {
        let lineKey = RendererKey.line
        let firstLine = lines.first?[lineKey]
            as? [String: Any]
        let items = firstLine?[JSONKey.items]
            as? [[String: Any]] ?? []
        let name = items.first.flatMap { li in
            let rdr = li[RendererKey.lineItem]
                as? [String: Any]
            return simpleText(
                from: rdr?[JSONKey.text]
            )
        } ?? ""
        return (name, items)
    }

    static func resolveTileThumb(
        videoId: String,
        tile: [String: Any]
    ) -> (url: String, raw: String) {
        let hdr = tile.digDict(
            JSONKey.header,
            RendererKey.tileHeader
        )
        let raw = hdr?.thumbnailURL() ?? ""
        let url = preferredThumbnailURL(
            videoId: videoId,
            fallbackURL: raw
        )
        return (url, raw)
    }

    static func parseTileOverlay(
        tile: [String: Any]
    ) -> (isLive: Bool, duration: String?) {
        let hdr = tile.digDict(
            JSONKey.header,
            RendererKey.tileHeader
        )
        let overlays = hdr?["thumbnailOverlays"]
            as? [[String: Any]] ?? []
        let isLive = checkOverlayLive(overlays)
        let duration: String? = isLive
            ? nil : overlayDuration(overlays)
        return (isLive, duration)
    }

    static func overlayDuration(
        _ overlays: [[String: Any]]
    ) -> String? {
        let key = RendererKey
            .thumbnailOverlayTimeStatus
        return overlays.compactMap { overlay in
            let rdr = overlay[key]
                as? [String: Any]
            return simpleText(
                from: rdr?[JSONKey.text]
            )
        }.first
    }

    static func parseTileTiming(
        lines: [[String: Any]]
    ) -> (viewCount: String?, publishedAt: String?) {
        guard lines.count > 1 else {
            return (nil, nil)
        }
        let lineDict = lines[1][RendererKey.line]
            as? [String: Any]
        let items = lineDict?[JSONKey.items]
            as? [[String: Any]] ?? []
        var viewCount: String?
        var publishedAt: String?
        for li in items {
            let rdr = li[RendererKey.lineItem]
                as? [String: Any]
            let text = simpleText(
                from: rdr?[JSONKey.text]
            ) ?? ""
            classifyTimingText(
                text,
                viewCount: &viewCount,
                publishedAt: &publishedAt
            )
        }
        return (viewCount, publishedAt)
    }

    static func classifyTimingText(
        _ text: String,
        viewCount: inout String?,
        publishedAt: inout String?
    ) {
        let skip = text == "•" || text == "·"
        guard !skip, !text.isEmpty else {
            return
        }
        if isViewCountText(text) {
            viewCount = text
        } else if isPublishedText(text) {
            publishedAt = text
        }
    }

    static func isViewCountText(
        _ text: String
    ) -> Bool {
        let keys = [
            "view", "просмотр",
            "watching", "смотр"
        ]
        return keys.contains { text.contains($0) }
    }

    static func isPublishedText(
        _ text: String
    ) -> Bool {
        let keys = [
            "ago", "назад", "hour", "day",
            "week", "month", "year", "час",
            "нед", "мес", "лет", "дн",
            "мин", "сек"
        ]
        return keys.contains { text.contains($0) }
    }
}
