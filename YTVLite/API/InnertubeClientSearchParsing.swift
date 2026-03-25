import Foundation

extension InnertubeClient {

    // MARK: - WEB search

    static func parseSearchFeed(_ data: Data) -> [Video] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let twoCol = (json["contents"] as? [String: Any])?["twoColumnSearchResultsRenderer"] as? [String: Any],
              let primary = twoCol["primaryContents"] as? [String: Any],
              let sectionList = primary["sectionListRenderer"] as? [String: Any],
              let sections = sectionList["contents"] as? [[String: Any]],
              let section = sections.first,
              let items = (section["itemSectionRenderer"] as? [String: Any])?["contents"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> Video? in
            guard let vr = item["videoRenderer"] as? [String: Any] else { return nil }
            let videoId = vr["videoId"] as? String ?? ""
            let title = (vr["title"] as? [String: Any]).flatMap {
                ($0["runs"] as? [[String: Any]])?.first?["text"] as? String } ?? ""
            let channel = (vr["ownerText"] as? [String: Any]).flatMap {
                ($0["runs"] as? [[String: Any]])?.first?["text"] as? String } ?? ""
            let channelId = (vr["ownerText"] as? [String: Any]).flatMap {
                ($0["runs"] as? [[String: Any]])?.first?["navigationEndpoint"] as? [String: Any]
            }.flatMap { ($0["browseEndpoint"] as? [String: Any])?["browseId"] as? String }
            let viewCount = (vr["viewCountText"] as? [String: Any])?["simpleText"] as? String
            let thumbs = (vr["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]] ?? []
            let rawThumbURL = thumbs.last?["url"] as? String ?? ""
            let thumbURL = preferredThumbnailURL(videoId: videoId, fallbackURL: rawThumbURL)
            let channelAvatarURL = (((vr["channelThumbnailSupportedRenderers"] as? [String: Any])?["channelThumbnailWithLinkRenderer"] as? [String: Any])?["thumbnail"] as? [String: Any])
                .flatMap { ($0["thumbnails"] as? [[String: Any]])?.last?["url"] as? String }
            guard !videoId.isEmpty else { return nil }
            logThumbnailChoice(videoId: videoId, chosenURL: thumbURL, fallbackURL: rawThumbURL)
            return Video(id: videoId, title: title, channelId: channelId,
                         channelName: channel, channelAvatarURL: channelAvatarURL,
                         thumbnailURL: thumbURL, viewCount: viewCount, publishedAt: nil, duration: nil)
        }
    }

    static func parseChannelInfo(_ json: [String: Any], fallbackChannelId: String) -> ChannelInfo? {
        if let header = firstRenderer(in: json, named: "channelHeaderRenderer") {
            let avatarURL = extractThumbnailURL(from: header["avatar"]) ??
                extractThumbnailURL(from: header["thumbnail"]) ??
                extractThumbnailURL(from: header["image"])
            let title =
                simpleText(from: header["title"]) ??
                header["title"] as? String ??
                simpleText(from: header["headline"]) ??
                ""
            let subscriberCountText =
                simpleText(from: header["subscriberCountText"]) ??
                simpleText(from: header["metadata"]) ??
                simpleText(from: header["subtitle"])
            let channelId = header["channelId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                //print("[Innertube] parseChannelInfo: channelHeaderRenderer matched for \(fallbackChannelId)")
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let avatarLockup = firstRenderer(in: json, named: "avatarLockupRenderer") {
            let avatarURL = extractThumbnailURL(from: avatarLockup["avatar"]) ??
                extractThumbnailURL(from: avatarLockup["thumbnail"])
            let title =
                simpleText(from: avatarLockup["title"]) ??
                simpleText(from: avatarLockup["text"]) ??
                ""
            let subscriberCountText =
                simpleText(from: avatarLockup["subtitle"]) ??
                simpleText(from: avatarLockup["accessibilityText"])
            let channelId = firstMatchingBrowseId(in: avatarLockup) ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                //print("[Innertube] parseChannelInfo: avatarLockupRenderer matched for \(fallbackChannelId)")
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let header = firstRenderer(in: json, named: "c4TabbedHeaderRenderer") {
            let avatarURL = ((header["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                .last?["url"] as? String
            let title = header["title"] as? String ?? ""
            let subscriberCountText = simpleText(from: header["subscriberCountText"])
            let channelId = header["channelId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let metadata = firstRenderer(in: json, named: "channelMetadataRenderer") {
            let avatarURL = ((metadata["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?
                .last?["url"] as? String
            let title = metadata["title"] as? String ?? ""
            let channelId = metadata["externalId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: nil)
            }
        }

        if let header = findChannelHeaderCandidate(in: json) {
            let avatarURL =
                ((header["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String ??
                ((header["boxArt"] as? [String: Any])?["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            let title =
                header["title"] as? String ??
                simpleText(from: header["title"]) ??
                simpleText(from: header["pageTitle"]) ??
                ""
            let subscriberCountText =
                simpleText(from: header["subscriberCountText"]) ??
                simpleText(from: header["metadata"]) ??
                simpleText(from: header["description"])
            let channelId = header["channelId"] as? String ?? fallbackChannelId

            if !title.isEmpty || avatarURL != nil {
                //print("[Innertube] parseChannelInfo: heuristic header matched for \(fallbackChannelId)")
                return ChannelInfo(id: channelId, title: title,
                                   avatarURL: avatarURL,
                                   subscriberCountText: subscriberCountText)
            }
        }

        if let tvBrowse = (json["contents"] as? [String: Any])?["tvBrowseRenderer"] as? [String: Any] {
            let topKeys = tvBrowse.keys.sorted().joined(separator: ", ")
            let headerKeys = (tvBrowse["header"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "nil"
            let contentKeys = (tvBrowse["content"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "nil"
            let rendererPaths = Array(collectRendererKeys(in: tvBrowse).prefix(30)).sorted().joined(separator: ", ")
            let thumbnailURLs = Array(collectThumbnailURLs(in: tvBrowse).prefix(10)).joined(separator: ", ")
            print("[Innertube] parseChannelInfo failed for \(fallbackChannelId). tvBrowse keys: \(topKeys). header keys: \(headerKeys). content keys: \(contentKeys)")
            print("[Innertube] channel renderers for \(fallbackChannelId): \(rendererPaths)")
            print("[Innertube] channel thumbnails for \(fallbackChannelId): \(thumbnailURLs)")
        } else {
            let topKeys = json.keys.sorted().joined(separator: ", ")
            print("[Innertube] parseChannelInfo failed for \(fallbackChannelId). top-level keys: \(topKeys)")
        }

        return nil
    }

    static func parseSubscribeState(_ json: [String: Any]) -> (text: String?, isSubscribed: Bool) {
        guard let renderer = firstRenderer(in: json, named: "subscribeButtonRenderer") else {
            return (nil, false)
        }

        let isSubscribed = renderer["subscribed"] as? Bool ?? false
        let text = simpleText(from: renderer["buttonText"]) ??
            simpleText(from: renderer["subscribedButtonText"]) ??
            simpleText(from: renderer["unsubscribedButtonText"])

        return (text, isSubscribed)
    }

    static func extractChannelId(from tile: [String: Any], firstLineItems: [[String: Any]]) -> String? {
        let candidatePaths: [[[String]]] = [
            [["lineItemRenderer"], ["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["onSelectCommand"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["command"], ["browseEndpoint"], ["browseId"]],
            [["lineItemRenderer"], ["text"], ["runs"], ["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["navigationEndpoint"], ["browseEndpoint"], ["browseId"]],
            [["onSelectCommand"], ["browseEndpoint"], ["browseId"]]
        ]

        for item in firstLineItems {
            for path in candidatePaths {
                if let browseId = nestedValue(in: item, path: path) as? String,
                   browseId.hasPrefix("UC") {
                    return browseId
                }
            }
        }

        if let browseId = firstMatchingBrowseId(in: tile), browseId.hasPrefix("UC") {
            return browseId
        }

        return nil
    }

    static func extractChannelAvatarURL(from tile: [String: Any]) -> String? {
        let candidatePaths: [[[String]]] = [
            [["metadata"], ["tileMetadataRenderer"], ["avatar"], ["thumbnails"]],
            [["metadata"], ["tileMetadataRenderer"], ["thumbnail"], ["thumbnails"]],
            [["metadata"], ["tileMetadataRenderer"], ["avatarThumbnail"], ["thumbnails"]],
            [["avatar"], ["thumbnails"]],
            [["channelThumbnailSupportedRenderers"], ["channelThumbnailWithLinkRenderer"], ["thumbnail"], ["thumbnails"]]
        ]

        for path in candidatePaths {
            if let thumbnails = nestedValue(in: tile, path: path) as? [[String: Any]],
               let url = thumbnails.last?["url"] as? String,
               !url.isEmpty {
                return url
            }
        }

        return nil
    }

    static func firstRenderer(in value: Any, named key: String) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let renderer = dict[key] as? [String: Any] {
                return renderer
            }

            for child in dict.values {
                if let renderer = firstRenderer(in: child, named: key) {
                    return renderer
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let renderer = firstRenderer(in: child, named: key) {
                    return renderer
                }
            }
        }

        return nil
    }

    static func firstMatchingBrowseId(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let browseId = dict["browseId"] as? String, browseId.hasPrefix("UC") {
                return browseId
            }

            for child in dict.values {
                if let browseId = firstMatchingBrowseId(in: child) {
                    return browseId
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let browseId = firstMatchingBrowseId(in: child) {
                    return browseId
                }
            }
        }

        return nil
    }

    static func findChannelHeaderCandidate(in value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            let hasAvatar = ((dict["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]]) != nil
            let hasBoxArt = ((dict["boxArt"] as? [String: Any])?["thumbnails"] as? [[String: Any]]) != nil
            let hasTitle = dict["title"] != nil || dict["pageTitle"] != nil
            let hasMetadata = dict["subscriberCountText"] != nil || dict["metadata"] != nil || dict["description"] != nil

            if (hasAvatar || hasBoxArt) && hasTitle && hasMetadata {
                return dict
            }

            for child in dict.values {
                if let candidate = findChannelHeaderCandidate(in: child) {
                    return candidate
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let candidate = findChannelHeaderCandidate(in: child) {
                    return candidate
                }
            }
        }

        return nil
    }

    static func collectRendererKeys(in value: Any) -> Set<String> {
        var result = Set<String>()

        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if key.hasSuffix("Renderer") {
                    result.insert(key)
                }
                result.formUnion(collectRendererKeys(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(collectRendererKeys(in: child))
            }
        }

        return result
    }

    static func collectThumbnailURLs(in value: Any) -> Set<String> {
        var result = Set<String>()

        if let dict = value as? [String: Any] {
            if let thumbnails = dict["thumbnails"] as? [[String: Any]] {
                for thumbnail in thumbnails {
                    if let url = thumbnail["url"] as? String, !url.isEmpty {
                        result.insert(url)
                    }
                }
            }

            for child in dict.values {
                result.formUnion(collectThumbnailURLs(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(collectThumbnailURLs(in: child))
            }
        }

        return result
    }

    static func collectTileRenderers(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []

        if let dict = value as? [String: Any] {
            if let tile = dict["tileRenderer"] as? [String: Any] {
                result.append(tile)
            }

            for child in dict.values {
                result.append(contentsOf: collectTileRenderers(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(contentsOf: collectTileRenderers(in: child))
            }
        }

        return result
    }

    static func extractThumbnailURL(from value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            if let thumbnails = dict["thumbnails"] as? [[String: Any]],
               let url = thumbnails.last?["url"] as? String,
               !url.isEmpty {
                return normalizeThumbnailURL(url)
            }

            for child in dict.values {
                if let url = extractThumbnailURL(from: child) {
                    return url
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let url = extractThumbnailURL(from: child) {
                    return url
                }
            }
        }

        return nil
    }

    static func normalizeThumbnailURL(_ url: String) -> String {
        if url.hasPrefix("//") {
            return "https:\(url)"
        }
        return url
    }

    static func preferredThumbnailURL(videoId: String, fallbackURL: String) -> String {
        guard !videoId.isEmpty else { return normalizeThumbnailURL(fallbackURL) }
        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    static func logThumbnailChoice(videoId: String, chosenURL: String, fallbackURL: String) {
        _ = videoId
        _ = chosenURL
        _ = fallbackURL
    }

    static func simpleText(from value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            if let text = dict["simpleText"] as? String, !text.isEmpty {
                return text
            }

            if let runs = dict["runs"] as? [[String: Any]] {
                let text = runs.compactMap { $0["text"] as? String }.joined()
                return text.isEmpty ? nil : text
            }
        }

        return nil
    }

    static func nestedValue(in root: [String: Any], path: [[String]]) -> Any? {
        var current: Any? = root

        for keys in path {
            guard let dict = current as? [String: Any] else { return nil }

            var next: Any?
            for key in keys {
                if let value = dict[key] {
                    next = value
                    break
                }
            }

            guard let resolved = next else { return nil }
            current = resolved
        }

        return current
    }

    static func buildCommentsContinuation(videoId: String, sortBy: Int, commentId: String?) -> String {
        let ctx = protoMessage([
            protoString(field: 2, value: videoId)
        ])

        let opts = protoMessage([
            protoString(field: 4, value: videoId),
            protoInt32(field: 6, value: sortBy),
            protoInt32(field: 15, value: 2),
            commentId.flatMap { protoString(field: 16, value: $0) }
        ].compactMap { $0 })

        let params = protoMessage([
            protoMessage(field: 4, value: opts),
            protoString(field: 8, value: "comments-section")
        ])

        let root = protoMessage([
            protoMessage(field: 2, value: ctx),
            protoInt32(field: 3, value: 6),
            protoMessage(field: 6, value: params)
        ])

        return percentEncode(base64URLEncoded(root))
    }

    static func protoMessage(_ fields: [Data]) -> Data {
        fields.reduce(into: Data(), { $0.append($1) })
    }

    static func protoMessage(field: Int, value: Data) -> Data {
        var data = Data()
        data.append(protoKey(field: field, wireType: 2))
        data.append(protoVarint(value.count))
        data.append(value)
        return data
    }

    static func protoString(field: Int, value: String) -> Data {
        protoMessage(field: field, value: Data(value.utf8))
    }

    static func protoInt32(field: Int, value: Int) -> Data {
        var data = Data()
        data.append(protoKey(field: field, wireType: 0))
        data.append(protoVarint(value))
        return data
    }

    static func protoKey(field: Int, wireType: Int) -> Data {
        protoVarint((field << 3) | wireType)
    }

    static func protoVarint(_ value: Int) -> Data {
        var data = Data()
        var current = UInt64(bitPattern: Int64(value))
        while current >= 0x80 {
            data.append(UInt8(current & 0x7F | 0x80))
            current >>= 7
        }
        data.append(UInt8(current))
        return data
    }

    static func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    static func collectCommentThreads(in value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []

        if let dict = value as? [String: Any] {
            if let renderer = dict["commentThreadRenderer"] as? [String: Any] {
                result.append(renderer)
            } else if dict["commentViewModel"] is [String: Any] {
                result.append(dict)
            }

            for child in dict.values {
                result.append(contentsOf: collectCommentThreads(in: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(contentsOf: collectCommentThreads(in: child))
            }
        }

        return result
    }

    static func parseComment(from thread: [String: Any], mutations: [[String: Any]]) -> Comment? {
        guard let viewModel = thread["commentViewModel"] as? [String: Any] else { return nil }
        guard let commentId = viewModel["commentId"] as? String else { return nil }

        let commentKey = viewModel["commentKey"] as? String
        let toolbarStateKey = viewModel["toolbarStateKey"] as? String
        let toolbarSurfaceKey = viewModel["toolbarSurfaceKey"] as? String

        let commentMutation = mutations.first {
            (($0["payload"] as? [String: Any])?["commentEntityPayload"] as? [String: Any])?["key"] as? String == commentKey
        }.flatMap { ($0["payload"] as? [String: Any])?["commentEntityPayload"] as? [String: Any] }

        let toolbarStateMutation = mutations.first {
            (($0["payload"] as? [String: Any])?["engagementToolbarStateEntityPayload"] as? [String: Any])?["key"] as? String == toolbarStateKey
        }.flatMap { ($0["payload"] as? [String: Any])?["engagementToolbarStateEntityPayload"] as? [String: Any] }

        let toolbarSurfaceMutation = mutations.first {
            ($0["entityKey"] as? String) == toolbarSurfaceKey
        }.flatMap { ($0["payload"] as? [String: Any])?["engagementToolbarSurfaceEntityPayload"] as? [String: Any] }

        let author = (commentMutation?["author"] as? [String: Any]) ?? [:]
        let toolbar = (commentMutation?["toolbar"] as? [String: Any]) ?? [:]
        let properties = (commentMutation?["properties"] as? [String: Any]) ?? [:]
        let avatar = commentMutation?["avatar"] as? [String: Any]

        let authorName = (author["displayName"] as? String)
            ?? simpleText(from: author["displayText"])
            ?? "Unknown"
        let authorChannelId = author["channelId"] as? String
        let authorAvatarURL = extractThumbnailURL(from: avatar?["image"])
        let content = attributedText(from: properties["content"]) ?? simpleText(from: properties["content"]) ?? ""
        let publishedTime = properties["publishedTime"] as? String
        let likeCount = (toolbar["likeCountNotliked"] as? String)
            ?? (toolbar["likeCountLiked"] as? String)
            ?? simpleText(from: toolbar["likeCountA11y"])
        let replyCount = (toolbar["replyCount"] as? String)
            ?? simpleText(from: toolbar["replyCountA11y"])
        let isPinned = viewModel["pinnedText"] != nil || thread["pinnedCommentBadge"] != nil
        let isDeleted = (toolbarStateMutation?["isDeleted"] as? Bool) == true
        let hasSurface = toolbarSurfaceMutation != nil || toolbar.isEmpty == false

        guard !isDeleted, !content.isEmpty || hasSurface else { return nil }

        return Comment(id: commentId,
                       authorName: authorName,
                       authorChannelId: authorChannelId,
                       authorAvatarURL: authorAvatarURL,
                       content: content,
                       publishedTime: publishedTime,
                       likeCount: likeCount,
                       replyCount: replyCount,
                       isPinned: isPinned)
    }

    static func attributedText(from value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let content = dict["content"] as? String, !content.isEmpty {
            return content
        }
        return simpleText(from: value)
    }

    static func findCommentsContinuation(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let renderer = dict["continuationItemRenderer"] as? [String: Any],
               let endpoint = renderer["continuationEndpoint"] as? [String: Any],
               let command = endpoint["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String,
               !token.isEmpty {
                return token
            }

            for child in dict.values {
                if let token = findCommentsContinuation(in: child) {
                    return token
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let token = findCommentsContinuation(in: child) {
                    return token
                }
            }
        }

        return nil
    }

    static func findCommentsTitle(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let renderer = dict["commentsHeaderRenderer"] as? [String: Any] {
                return simpleText(from: renderer["countText"])
                    ?? simpleText(from: renderer["commentsCount"])
                    ?? simpleText(from: renderer["titleText"])
            }

            if let renderer = dict["commentsEntryPointHeaderRenderer"] as? [String: Any] {
                return simpleText(from: renderer["commentCount"]) ?? simpleText(from: renderer["headerText"])
            }

            for child in dict.values {
                if let title = findCommentsTitle(in: child) {
                    return title
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let title = findCommentsTitle(in: child) {
                    return title
                }
            }
        }

        return nil
    }

}
