import Foundation

extension InnertubeClient {
    struct ChannelFields {
        let id: String
        let title: String
        let avatarURL: String?
        var subscriberCountText: String?
        var bannerURL: String?
        var isVerified = false
        var desc: String?
        var contactInfo: String?
        var videoCountText: String?
    }

    static func buildChannelInfo(
        _ fields: ChannelFields
    ) -> ChannelInfo? {
        guard !fields.title.isEmpty
            || fields.avatarURL != nil
        else {
            return nil
        }
        return ChannelInfo(
            id: fields.id,
            title: fields.title,
            avatarURL: fields.avatarURL,
            subscriberCountText: fields.subscriberCountText,
            bannerURL: fields.bannerURL,
            isVerified: fields.isVerified,
            description: fields.desc,
            contactInfo: fields.contactInfo,
            videoCountText: fields.videoCountText
        )
    }

    static func parseSubscribeState(
        _ json: [String: Any]
    ) -> (text: String?, isSubscribed: Bool) {
        guard let renderer = firstRenderer(
            in: json,
            named: "subscribeButtonRenderer"
        )
        else {
            return parseToggleSubscribe(json)
        }
        let isSubscribed = renderer["subscribed"]
            as? Bool ?? false
        let text: String? = subscribeText(
            renderer,
            isSubscribed: isSubscribed
        )
        AppLog.subscribe(
            "subscribeButtonRenderer:"
                + " subscribed=\(isSubscribed),"
                + " text=\(text ?? "nil")"
        )
        return (text, isSubscribed)
    }

    static func extractChannelId(
        from tile: [String: Any],
        firstLineItems: [[String: Any]]
    ) -> String? {
        for item in firstLineItems {
            for path in channelIdPaths {
                if let bid = nestedValue(
                    in: item, path: path
                ) as? String, bid.hasPrefix("UC") {
                    return bid
                }
            }
        }
        if let bid = firstMatchingBrowseId(in: tile),
           bid.hasPrefix("UC") {
            return bid
        }
        return nil
    }

    static func extractChannelAvatarURL(
        from tile: [String: Any]
    ) -> String? {
        for path in channelAvatarPaths {
            if let thumbs = nestedValue(
                in: tile, path: path
            ) as? [[String: Any]],
               let url = thumbs.last?["url"] as? String,
               !url.isEmpty {
                return url
            }
        }
        return nil
    }
}

private extension InnertubeClient {
    static var channelIdPaths: [[[String]]] {
        let textPath: [[String]] = [
            ["lineItemRenderer"],
            ["text"],
            ["runs"],
            ["navigationEndpoint"],
            ["browseEndpoint"],
            ["browseId"]
        ]
        return [
            [["lineItemRenderer"], ["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["onSelectCommand"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["command"], ["browseEndpoint"], ["browseId"]],
            textPath,
            [["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["onSelectCommand"], ["browseEndpoint"], ["browseId"]]
        ]
    }

    static var channelAvatarPaths: [[[String]]] {
        let ctPath: [[String]] = [
            ["channelThumbnailSupportedRenderers"],
            ["channelThumbnailWithLinkRenderer"],
            ["thumbnail"],
            ["thumbnails"]
        ]
        return [
            [["metadata"], ["tileMetadataRenderer"], ["avatar"], ["thumbnails"]],
            [["metadata"], ["tileMetadataRenderer"], ["thumbnail"], ["thumbnails"]],
            [["metadata"], ["tileMetadataRenderer"], ["avatarThumbnail"], ["thumbnails"]],
            [["avatar"], ["thumbnails"]],
            ctPath
        ]
    }

    static func parseToggleSubscribe(
        _ json: [String: Any]
    ) -> (text: String?, isSubscribed: Bool) {
        if let toggle = firstRenderer(
            in: json,
            named: "toggleButtonRenderer"
        ) {
            let isSub = toggle["isToggled"]
                as? Bool ?? false
            let text = simpleText(
                from: toggle["defaultText"]
            ) ?? simpleText(from: toggle["toggledText"])
            AppLog.subscribe(
                "toggleButtonRenderer found,"
                    + " isToggled=\(isSub),"
                    + " text=\(text ?? "nil")"
            )
            return (text, isSub)
        }
        AppLog.subscribe(
            "no subscribeButtonRenderer"
                + " or toggleButtonRenderer found"
        )
        return (nil, false)
    }

    static func subscribeText(
        _ renderer: [String: Any],
        isSubscribed: Bool
    ) -> String? {
        if isSubscribed {
            return simpleText(
                from: renderer["buttonText"]
            ) ?? simpleText(
                from: renderer["subscribedButtonText"]
            )
        }
        return simpleText(
            from: renderer["buttonText"]
        ) ?? simpleText(
            from: renderer["unsubscribedButtonText"]
        )
    }
}
