import Foundation

extension InnertubeClient {
    static func parsePageJSON(
        _ json: [String: Any]
    ) -> FeedPage {
        if let cc = json["continuationContents"]
            as? [String: Any] {
            return parseContinuationContents(cc)
        }
        if let slr = extractSectionList(
            from: json
        ) {
            return parseSectionList(slr)
        }
        let keys = (json["contents"]
            as? [String: Any])?
            .keys.joined(separator: ", ") ?? "nil"
        AppLog.innertube(
            "parsePageJSON: unrecognized."
                + " keys: \(keys)"
        )
        return FeedPage(
            videos: [],
            continuation: nil
        )
    }

    static func extractSectionList(
        from json: [String: Any]
    ) -> [String: Any]? {
        let ct = json["contents"] as? [String: Any]
        let browse = ct?["tvBrowseRenderer"]
            as? [String: Any]
        let content = browse?["content"]
            as? [String: Any]
        if let slr = homeFeedSectionList(content) {
            return slr
        }
        return subscriptionsSectionList(content)
    }

    static func parseSectionList(
        _ slr: [String: Any]
    ) -> FeedPage {
        let sections = slr["contents"]
            as? [[String: Any]] ?? []
        var videos: [Video] = []
        for section in sections {
            guard let shelf = section[
                "shelfRenderer"
            ] as? [String: Any],
                  let sc = shelf["content"]
                    as? [String: Any]
            else {
                continue
            }
            appendShelfVideos(
                from: sc, into: &videos
            )
        }
        return FeedPage(
            videos: videos,
            continuation: nextContToken(slr)
        )
    }
}

// MARK: - Private Helpers

private extension InnertubeClient {
    static func parseContinuationContents(
        _ cc: [String: Any]
    ) -> FeedPage {
        if let slr = cc["sectionListContinuation"]
            as? [String: Any] {
            return parseSectionList(slr)
        }
        if let gc = cc["gridContinuation"]
            as? [String: Any] {
            return parseGridContinuation(gc)
        }
        if let rgc = cc["richGridContinuation"]
            as? [String: Any] {
            return parseRichGridCont(rgc)
        }
        AppLog.innertube(
            "parsePageJSON: unknown continuation"
                + " keys: \(cc.keys.sorted())"
        )
        return FeedPage(
            videos: [],
            continuation: nil
        )
    }

    static func parseGridContinuation(
        _ gc: [String: Any]
    ) -> FeedPage {
        let items = gc[JSONKey.items]
            as? [[String: Any]] ?? []
        return FeedPage(
            videos: VideoRendererParserChain
                .videos(from: items),
            continuation: nextContToken(gc)
        )
    }

    static func parseRichGridCont(
        _ rgc: [String: Any]
    ) -> FeedPage {
        let items = rgc[JSONKey.contents]
            as? [[String: Any]] ?? []
        let parsed = VideoRendererParserChain
            .parse(items: items)
        return FeedPage(
            videos: parsed.videos,
            continuation: parsed.continuation
        )
    }

    static func nextContToken(
        _ container: [String: Any]
    ) -> String? {
        let conts = container[
            JSONKey.continuations
        ] as? [[String: Any]]
        let next = conts?.first?[
            "nextContinuationData"
        ] as? [String: Any]
        return next?[JSONKey.continuation]
            as? String
    }

    static func homeFeedSectionList(
        _ content: [String: Any]?
    ) -> [String: Any]? {
        let surface = content?[
            "tvSurfaceContentRenderer"
        ] as? [String: Any]
        return (surface?["content"]
            as? [String: Any])?[
                "sectionListRenderer"
            ] as? [String: Any]
    }

    static func subscriptionsSectionList(
        _ content: [String: Any]?
    ) -> [String: Any]? {
        let nav = content?[
            "tvSecondaryNavRenderer"
        ] as? [String: Any]
        let sections = nav?["sections"]
            as? [[String: Any]]
        let nr = sections?.first?[
            "tvSecondaryNavSectionRenderer"
        ] as? [String: Any]
        let tabs = nr?["tabs"]
            as? [[String: Any]]
        let tr = tabs?.first?["tabRenderer"]
            as? [String: Any]
        let tc = tr?["content"] as? [String: Any]
        let surface = tc?[
            "tvSurfaceContentRenderer"
        ] as? [String: Any]
        return (surface?["content"]
            as? [String: Any])?[
                "sectionListRenderer"
            ] as? [String: Any]
    }

    static func appendShelfVideos(
        from shelfContent: [String: Any],
        into videos: inout [Video]
    ) {
        let keys = [
            "horizontalListRenderer",
            "verticalListRenderer",
            "gridRenderer"
        ]
        for key in keys {
            let rd = shelfContent[key]
                as? [String: Any]
            if let items = rd?["items"]
                as? [[String: Any]] {
                videos.append(
                    contentsOf:
                        VideoRendererParserChain
                        .videos(from: items)
                )
            }
        }
    }
}
