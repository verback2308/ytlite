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
}
