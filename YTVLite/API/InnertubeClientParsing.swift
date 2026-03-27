import Foundation

extension InnertubeClient {
    static func parseWatchPage(
        _ json: [String: Any],
        fallbackVideo fb: Video
    ) -> WatchPage? {
        let ch = parseWatchChannelInfo(
            json, fallbackVideo: fb
        )
        let sub = parseSubscribeState(json)
        let likeInfo = parseWatchLikeInfo(json)
        return WatchPage(
            video: resolvedVideo(
                fb, from: json, channel: ch
            ),
            description: parseWatchDescription(json),
            channelInfo: ch,
            subscribeButtonText: sub.text,
            isSubscribed: sub.isSubscribed,
            relatedVideos: deduplicatedRelated(
                json: json, excludingId: fb.id
            ),
            likeCount: likeInfo.likeCount,
            likeStatus: likeInfo.likeStatus,
            nextVideo: autoplayNextVideo(json)
        )
    }

    static func parseWatchLikeInfo(
        _ json: [String: Any]
    ) -> (
        likeCount: String?,
        likeStatus: LikeStatus?
    ) {
        if let renderer = firstRenderer(
            in: json,
            named: "slimVideoActionsRenderer"
        ),
           let buttons = renderer["buttons"]
            as? [[String: Any]] {
            if let result = searchLikeButtons(
                buttons
            ) {
                return result
            }
        }
        if let renderer = firstRenderer(
            in: json,
            named: "likeButtonRenderer"
        ) {
            return parseLikeRenderer(renderer)
        }
        return (nil, nil)
    }

    static func parseCommentsPage(
        _ json: [String: Any]
    ) -> CommentsPage? {
        let updates = json["frameworkUpdates"]
            as? [String: Any]
        let batch = updates?["entityBatchUpdate"]
            as? [String: Any]
        let mutations = batch?["mutations"]
            as? [[String: Any]] ?? []
        let threads = collectCommentThreads(
            in: json
        )
        let comments = threads.compactMap {
            parseComment(
                from: $0, mutations: mutations
            )
        }
        let cont = findCommentsContinuation(
            in: json
        )
        let title = findCommentsTitle(in: json)
        guard !comments.isEmpty || cont != nil
        else {
            return nil
        }
        return CommentsPage(
            title: title,
            comments: comments,
            continuation: cont
        )
    }
}

// MARK: - Private Watch Helpers

private extension InnertubeClient {
    static func resolvedVideo(
        _ fb: Video,
        from json: [String: Any],
        channel: ChannelInfo?
    ) -> Video {
        let meta = parseWatchMetadata(json)
        let name: String
        if let ch = channel?.title, !ch.isEmpty {
            name = ch
        } else {
            name = fb.channelName
        }
        return Video(
            id: fb.id,
            title: meta.title ?? fb.title,
            channelId: channel?.id
                ?? fb.channelId,
            channelName: name,
            channelAvatarURL: channel?.avatarURL
                ?? fb.channelAvatarURL,
            thumbnailURL: fb.thumbnailURL,
            viewCount: meta.viewCountText
                ?? fb.viewCount,
            publishedAt: meta.publishedText
                ?? fb.publishedAt,
            duration: fb.duration,
            isLive: fb.isLive
        )
    }

    static func deduplicatedRelated(
        json: [String: Any],
        excludingId: String
    ) -> [Video] {
        collectTileRenderers(in: json)
            .compactMap(parseTileRenderer)
            .filter { $0.id != excludingId }
            .reduce(
                into: [Video]()
            ) { result, video in
                guard !result.contains(
                    where: { $0.id == video.id }
                ) else {
                    return
                }
                result.append(video)
            }
    }

    static func autoplayNextVideo(
        _ json: [String: Any]
    ) -> Video? {
        let po = json["playerOverlays"]
            as? [String: Any]
        let ovr = po?["playerOverlayRenderer"]
            as? [String: Any]
        let ap = ovr?["autoplay"]
            as? [String: Any]
        let key = "playerOverlayAutoplayRenderer"
        guard let ar = ap?[key]
            as? [String: Any],
              let vid = ar["videoId"] as? String
        else {
            return nil
        }
        return buildAutoplayVideo(
            ar, videoId: vid
        )
    }

    static func buildAutoplayVideo(
        _ ar: [String: Any],
        videoId: String
    ) -> Video {
        let vt = ar["videoTitle"]
            as? [String: Any]
        let title = vt?["simpleText"]
            as? String ?? ""
        let byline = ar["byline"]
            as? [String: Any]
        let channel = byline?["simpleText"]
            as? String ?? ""
        let bg = ar["background"]
            as? [String: Any]
        let thumbs = bg?["thumbnails"]
            as? [[String: Any]]
        let thumbURL =
            thumbs?.last?["url"] as? String
            ?? thumbs?.first?["url"] as? String
            ?? AppURLs.YouTube.thumbnailURL(
                videoId: videoId
            )
        return Video(
            id: videoId,
            title: title,
            channelId: nil,
            channelName: channel,
            channelAvatarURL: nil,
            thumbnailURL: thumbURL,
            viewCount: nil,
            publishedAt: nil,
            duration: nil
        )
    }

    static func searchLikeButtons(
        _ buttons: [[String: Any]]
    ) -> (
        likeCount: String?,
        likeStatus: LikeStatus?
    )? {
        let key = "slimMetadataToggleButtonRenderer"
        for btn in buttons {
            if let like = (btn[key]
                as? [String: Any])
                ?? (btn["likeButtonRenderer"]
                    as? [String: Any]) {
                return extractLikeInfo(from: like)
            }
            if let toggle = btn[
                "toggleButtonRenderer"
            ] as? [String: Any] {
                return extractLikeInfo(from: toggle)
            }
        }
        return nil
    }

    static func extractLikeInfo(
        from dict: [String: Any]
    ) -> (
        likeCount: String?,
        likeStatus: LikeStatus?
    ) {
        let status = (dict["likeStatus"]
            as? String)
            .flatMap(LikeStatus.init(rawValue:))
        let count = simpleText(
            from: dict["defaultText"]
        ) ?? simpleText(
            from: dict["likeCountNotliked"]
        )
        return (count, status)
    }

    static func parseLikeRenderer(
        _ renderer: [String: Any]
    ) -> (
        likeCount: String?,
        likeStatus: LikeStatus?
    ) {
        let status = (renderer["likeStatus"]
            as? String)
            .flatMap(LikeStatus.init(rawValue:))
        let count = simpleText(
            from: renderer["likeCount"]
        ) ?? (renderer["likeCountNotliked"]
            as? String)
        return (count, status)
    }
}
