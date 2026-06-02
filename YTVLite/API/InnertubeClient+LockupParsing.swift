import Foundation

extension InnertubeClient {
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

    static func playlistItemCount(from text: String?) -> Int? {
        guard let text else {
            return nil
        }
        let digits = text.filter { $0.isNumber }
        return Int(digits)
    }

    // MARK: - Video lockup

    static func parseLockupVideo(_ lockup: [String: Any]) -> Video? {
        guard let videoId = lockup["contentId"] as? String,
              let title = playlistTitle(from: lockup)
        else { return nil }
        let thumbnail = lockupVideoThumbnailURL(from: lockup)
            ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
        let (duration, isLive) = lockupVideoDuration(from: lockup)
        let (viewCount, publishedAt) = lockupVideoMeta(from: lockup)
        return Video(
            id: videoId,
            title: title,
            channelId: nil,
            channelName: "",
            channelAvatarURL: nil,
            thumbnailURL: thumbnail,
            viewCount: viewCount,
            publishedAt: publishedAt,
            duration: duration,
            isLive: isLive
        )
    }

    private static func lockupVideoDuration(
        from lockup: [String: Any]
    ) -> (duration: String?, isLive: Bool) {
        let overlays = lockup.digArray("thumbnail", "thumbnailViewModel", "overlays") ?? []
        for overlay in overlays {
            guard let ts = overlay["thumbnailOverlayTimeStatusViewModel"] as? [String: Any]
            else { continue }
            if (ts["style"] as? String) == "LIVE" {
                return (nil, true)
            }
            return (ts.digString(JSONKey.text, JSONKey.content), false)
        }
        return (nil, false)
    }

    private static func lockupVideoMeta(
        from lockup: [String: Any]
    ) -> (viewCount: String?, publishedAt: String?) {
        let rows = lockup.digArray(
            "metadata",
            "lockupMetadataViewModel",
            "metadata",
            "contentMetadataViewModel",
            "metadataRows"
        ) ?? []
        for row in rows {
            guard let parts = row["metadataParts"] as? [[String: Any]] else { continue }
            let texts = parts.compactMap { $0.digString(JSONKey.text, JSONKey.content) }
            if !texts.isEmpty {
                return (texts.first, texts.dropFirst().first)
            }
        }
        return (nil, nil)
    }

    private static func lockupVideoThumbnailURL(from lockup: [String: Any]) -> String? {
        let url = lockup.digString(
            "thumbnail", "thumbnailViewModel", "image", "sources", 0, JSONKey.url
        )
        return url.map(normalizeThumbnailURL)
    }
}
