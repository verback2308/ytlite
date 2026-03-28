import Foundation

extension InnertubeClient {
    static func firstRenderer(
        in value: Any,
        named key: String
    ) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if let renderer = dict[key] as? [String: Any] {
                return renderer
            }
            for child in dict.values {
                if let found = firstRenderer(
                    in: child, named: key
                ) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstRenderer(
                    in: child, named: key
                ) {
                    return found
                }
            }
        }
        return nil
    }

    static func firstMatchingBrowseId(
        in value: Any
    ) -> String? {
        if let dict = value as? [String: Any] {
            if let bid = dict["browseId"] as? String,
               bid.hasPrefix("UC") {
                return bid
            }
            for child in dict.values {
                if let bid = firstMatchingBrowseId(
                    in: child
                ) {
                    return bid
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let bid = firstMatchingBrowseId(
                    in: child
                ) {
                    return bid
                }
            }
        }
        return nil
    }

    static func simpleText(from value: Any?) -> String? {
        if let dict = value as? [String: Any] {
            if let text = dict["simpleText"] as? String,
               !text.isEmpty {
                return text
            }
            if let runs = dict["runs"] as? [[String: Any]] {
                let text = runs
                    .compactMap { $0["text"] as? String }
                    .joined()
                return text.isEmpty ? nil : text
            }
        }
        return nil
    }

    static func nestedValue(
        in root: [String: Any],
        path: [[String]]
    ) -> Any? {
        var current: Any? = root
        for keys in path {
            guard let dict = current as? [String: Any]
            else {
                return nil
            }
            var next: Any?
            for key in keys {
                if let value = dict[key] {
                    next = value
                    break
                }
            }
            guard let resolved = next
            else {
                return nil
            }
            current = resolved
        }
        return current
    }

    static func extractThumbnailURL(
        from value: Any?
    ) -> String? {
        if let dict = value as? [String: Any] {
            if let thumbs = dict["thumbnails"]
                as? [[String: Any]],
               let url = thumbs.last?["url"] as? String,
               !url.isEmpty {
                return normalizeThumbnailURL(url)
            }
            for child in dict.values {
                if let url = extractThumbnailURL(
                    from: child
                ) {
                    return url
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let url = extractThumbnailURL(
                    from: child
                ) {
                    return url
                }
            }
        }
        return nil
    }

    static func normalizeThumbnailURL(
        _ url: String
    ) -> String {
        if url.hasPrefix("//") {
            return "https:\(url)"
        }
        return url
    }

    static func preferredThumbnailURL(
        videoId: String,
        fallbackURL: String
    ) -> String {
        guard !videoId.isEmpty
        else {
            return normalizeThumbnailURL(fallbackURL)
        }
        return AppURLs.YouTube.thumbnailURL(
            videoId: videoId
        )
    }

    static func logThumbnailChoice(
        videoId: String,
        chosenURL: String,
        fallbackURL: String
    ) {
        _ = videoId
        _ = chosenURL
        _ = fallbackURL
    }

    static func thumbnailsLastURL(
        _ value: Any?
    ) -> String {
        guard let dict = value as? [String: Any],
              let thumbs = dict["thumbnails"]
                as? [[String: Any]],
              let url = thumbs.last?["url"] as? String
        else {
            return ""
        }
        return url
    }

    static func findChannelHeaderCandidate(
        in value: Any
    ) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if isChannelCandidate(dict) {
                return dict
            }
            for child in dict.values {
                if let found = findChannelHeaderCandidate(
                    in: child
                ) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findChannelHeaderCandidate(
                    in: child
                ) {
                    return found
                }
            }
        }
        return nil
    }

    static func collectRendererKeys(
        in value: Any
    ) -> Set<String> {
        var result = Set<String>()
        if let dict = value as? [String: Any] {
            for (key, child) in dict {
                if key.hasSuffix("Renderer") {
                    result.insert(key)
                }
                result.formUnion(
                    collectRendererKeys(in: child)
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(
                    collectRendererKeys(in: child)
                )
            }
        }
        return result
    }

    static func collectThumbnailURLs(
        in value: Any
    ) -> Set<String> {
        var result = Set<String>()
        if let dict = value as? [String: Any] {
            if let thumbs = dict["thumbnails"]
                as? [[String: Any]] {
                for thumb in thumbs {
                    if let url = thumb["url"] as? String,
                       !url.isEmpty {
                        result.insert(url)
                    }
                }
            }
            for child in dict.values {
                result.formUnion(
                    collectThumbnailURLs(in: child)
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.formUnion(
                    collectThumbnailURLs(in: child)
                )
            }
        }
        return result
    }

    static func collectTileRenderers(
        in value: Any
    ) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let dict = value as? [String: Any] {
            if let tile = dict["tileRenderer"]
                as? [String: Any] {
                result.append(tile)
            }
            for child in dict.values {
                result.append(
                    contentsOf: collectTileRenderers(
                        in: child
                    )
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(
                    contentsOf: collectTileRenderers(
                        in: child
                    )
                )
            }
        }
        return result
    }
}

private extension InnertubeClient {
    static func isChannelCandidate(
        _ dict: [String: Any]
    ) -> Bool {
        let hasAvatar = (dict["avatar"]
            as? [String: Any])?["thumbnails"]
            is [[String: Any]]
        let hasBoxArt = (dict["boxArt"]
            as? [String: Any])?["thumbnails"]
            is [[String: Any]]
        let hasTitle = dict["title"] != nil
            || dict["pageTitle"] != nil
        let hasMeta = dict["subscriberCountText"] != nil
            || dict["metadata"] != nil
            || dict["description"] != nil
        return (hasAvatar || hasBoxArt)
            && hasTitle && hasMeta
    }
}
