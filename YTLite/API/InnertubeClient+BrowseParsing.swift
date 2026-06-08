import Foundation

// MARK: - Browse Parsing
extension InnertubeClient {
    static func parseTVHistoryPage(
        _ json: [String: Any]
    ) -> FeedPage {
        if let page = parseTVHistoryCont(json) {
            return page
        }
        if let page = parseTVHistoryGrid(json) {
            return page
        }
        if let slr = extractSectionList(from: json) {
            return parseSectionList(slr)
        }
        if let page = parseTwoColumnBrowse(json) {
            return page
        }
        if let page = parseDirectSectionList(json) {
            return page
        }
        if let page = parseRichGridFeed(json) {
            return page
        }
        let keys = json.keys.sorted()
        AppLog.innertube(
            "parseTVHistoryPage: unknown "
                + "structure. topKeys=\(keys)"
        )
        if let cd = json[JSONKey.contents]
            as? [String: Any] {
            AppLog.innertube(
                "contentsKeys=\(cd.keys.sorted())"
            )
        }
        return FeedPage(videos: [], continuation: nil)
    }

    static func parseWebBrowsePage(
        _ json: [String: Any]
    ) -> FeedPage {
        if let page = parseWebContinuation(json) {
            return page
        }
        var videos: [Video] = []
        var continuation: String?
        parseWebBrowseTabs(
            json,
            videos: &videos,
            continuation: &continuation
        )
        appendRichGrid(
            from: json,
            videos: &videos,
            continuation: &continuation
        )
        return FeedPage(
            videos: videos,
            continuation: continuation
        )
    }

    static func parseWebSectionList(
        _ slr: [String: Any]
    ) -> FeedPage {
        let sections = slr[JSONKey.contents]
            as? [[String: Any]] ?? []
        var videos: [Video] = []
        var continuation: String?
        for section in sections {
            parseFeedSection(
                section,
                videos: &videos,
                continuation: &continuation
            )
        }
        return FeedPage(
            videos: videos,
            continuation: continuation
        )
    }
}

// MARK: - Private Browse Helpers
private extension InnertubeClient {
    static func parseTVHistoryCont(
        _ json: [String: Any]
    ) -> FeedPage? {
        guard let cc = json["continuationContents"]
            as? [String: Any]
        else {
            return nil
        }
        if let gc = cc["gridContinuation"]
            as? [String: Any],
           let items = gc["items"]
            as? [[String: Any]] {
            let vids = VideoRendererParserChain
                .videos(from: items)
            let cont = nextContToken(from: gc)
            AppLog.innertube(
                "TV history gridContinuation: "
                    + "\(vids.count) more videos"
            )
            return FeedPage(
                videos: vids, continuation: cont
            )
        }
        if let slr = cc["sectionListContinuation"]
            as? [String: Any] {
            return parseSectionList(slr)
        }
        return nil
    }

    static func parseTVHistoryGrid(
        _ json: [String: Any]
    ) -> FeedPage? {
        guard let grid = json.digDict(
            JSONKey.contents,
            RendererKey.tvBrowse,
            JSONKey.content,
            RendererKey.tvSurfaceContent,
            JSONKey.content,
            RendererKey.grid
        ),
              let items = grid[JSONKey.items]
            as? [[String: Any]]
        else {
            return nil
        }
        let videos = VideoRendererParserChain
            .videos(from: items)
        let cont = nextContToken(from: grid)
        AppLog.innertube(
            "TV history gridRenderer: "
                + "\(videos.count) videos"
        )
        return FeedPage(
            videos: videos, continuation: cont
        )
    }

    static func nextContToken(
        from dict: [String: Any]
    ) -> String? {
        let items = dict["continuations"]
            as? [[String: Any]]
        return items?.first.flatMap {
            let data = $0["nextContinuationData"]
                as? [String: Any]
            return data?["continuation"] as? String
        }
    }

    static func parseWebContinuation(
        _ json: [String: Any]
    ) -> FeedPage? {
        guard let cc = json["continuationContents"]
            as? [String: Any]
        else {
            return nil
        }
        if let slr = cc["sectionListContinuation"]
            as? [String: Any] {
            return parseWebSectionList(slr)
        }
        if let rgc = cc["richGridContinuation"]
            as? [String: Any] {
            let items = rgc[JSONKey.contents]
                as? [[String: Any]] ?? []
            let parsed = VideoRendererParserChain
                .parse(items: items)
            return FeedPage(
                videos: parsed.videos,
                continuation: parsed.continuation
            )
        }
        return nil
    }
}
