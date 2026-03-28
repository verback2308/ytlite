import Foundation

// MARK: - Browse Helpers
extension InnertubeClient {
    static func parseTwoColumnBrowse(
        _ json: [String: Any]
    ) -> FeedPage? {
        guard let tcbr = json.digDict(
            JSONKey.contents,
            RendererKey.twoColumnBrowse
        ) else {
            return nil
        }
        var videos: [Video] = []
        var continuation: String?
        let tabList = tcbr[JSONKey.tabs]
            as? [[String: Any]] ?? []
        for tab in tabList {
            guard let slr = tab.digDict(
                RendererKey.tab,
                JSONKey.content,
                RendererKey.sectionList
            ) else { continue }
            let page = parseWebSectionList(slr)
            videos.append(contentsOf: page.videos)
            if continuation == nil {
                continuation = page.continuation
            }
        }
        guard !videos.isEmpty else {
            return nil
        }
        return FeedPage(
            videos: videos,
            continuation: continuation
        )
    }

    static func parseDirectSectionList(
        _ json: [String: Any]
    ) -> FeedPage? {
        guard let slr = json.digDict(
            JSONKey.contents,
            RendererKey.sectionList
        ) else {
            return nil
        }
        let page = parseWebSectionList(slr)
        guard !page.videos.isEmpty else {
            return nil
        }
        return page
    }

    static func parseRichGridFeed(
        _ json: [String: Any]
    ) -> FeedPage? {
        guard let rg = json.digDict(
            JSONKey.contents,
            RendererKey.richGrid
        ),
              let items = rg[JSONKey.contents]
            as? [[String: Any]]
        else {
            return nil
        }
        let parsed = VideoRendererParserChain
            .parse(items: items)
        guard !parsed.videos.isEmpty else {
            return nil
        }
        return FeedPage(
            videos: parsed.videos,
            continuation: parsed.continuation
        )
    }

    static func parseWebBrowseTabs(
        _ json: [String: Any],
        videos: inout [Video],
        continuation: inout String?
    ) {
        let twoCols = json.digDict(
            JSONKey.contents,
            RendererKey.twoColumnBrowse
        )
        let tabList = twoCols?[JSONKey.tabs]
            as? [[String: Any]] ?? []
        for tab in tabList {
            guard let slr = tab.digDict(
                RendererKey.tab,
                JSONKey.content,
                RendererKey.sectionList
            ) else { continue }
            let page = parseWebSectionList(slr)
            videos.append(contentsOf: page.videos)
            if continuation == nil {
                continuation = page.continuation
            }
        }
    }

    static func appendRichGrid(
        from json: [String: Any],
        videos: inout [Video],
        continuation: inout String?
    ) {
        guard videos.isEmpty else {
            return
        }
        guard let rg = json.digDict(
            JSONKey.contents,
            RendererKey.richGrid
        ),
              let items = rg[JSONKey.contents]
            as? [[String: Any]]
        else {
            return
        }
        let parsed = VideoRendererParserChain
            .parse(items: items)
        videos.append(contentsOf: parsed.videos)
        if parsed.continuation != nil {
            continuation = parsed.continuation
        }
    }

    static func parseFeedSection(
        _ section: [String: Any],
        videos: inout [Video],
        continuation: inout String?
    ) {
        if let isr = section[
            RendererKey.itemSection
        ] as? [String: Any],
           let items = isr[JSONKey.contents]
            as? [[String: Any]] {
            videos.append(
                contentsOf: VideoRendererParserChain
                    .videos(from: items)
            )
        }
        parseShelfVideos(section, videos: &videos)
        parseSectionContinuation(
            section,
            continuation: &continuation
        )
    }

    static func parseShelfVideos(
        _ section: [String: Any],
        videos: inout [Video]
    ) {
        guard let shelf = section[RendererKey.shelf]
            as? [String: Any],
              let content = shelf[JSONKey.content]
            as? [String: Any]
        else {
            return
        }
        let listKeys = [
            RendererKey.verticalList,
            RendererKey.horizontalList
        ]
        for key in listKeys {
            let list = content[key]
                as? [String: Any]
            if let items = list?[JSONKey.items]
                as? [[String: Any]] {
                videos.append(
                    contentsOf: VideoRendererParserChain
                        .videos(from: items)
                )
            }
        }
        if let items = content[JSONKey.contents]
            as? [[String: Any]] {
            videos.append(
                contentsOf: VideoRendererParserChain
                    .videos(from: items)
            )
        }
    }

    static func parseSectionContinuation(
        _ section: [String: Any],
        continuation: inout String?
    ) {
        guard let ct = section[
            RendererKey.continuationItem
        ] as? [String: Any] else {
            return
        }
        let tok = ct.digString(
            "continuationEndpoint",
            "continuationCommand",
            JSONKey.token
        )
        if let tok {
            continuation = tok
        }
    }
}
