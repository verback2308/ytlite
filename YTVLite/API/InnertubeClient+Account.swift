import Foundation

// MARK: - Account

extension InnertubeClient {
    // MARK: Type Methods

    static func parseAccountsListJSON(
        _ json: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        if let headerResult = parseHeaderAccount(json) {
            return headerResult
        }
        if let sectionResult = parseAccountSections(json) {
            return sectionResult
        }
        return deepSearchAccountInfo(in: json)
    }

    static func deepSearchAccountInfo(
        in value: Any
    ) -> (name: String, avatarURL: String?)? {
        if let dict = value as? [String: Any] {
            if let result = extractAccountNameAndPhoto(from: dict) {
                return result
            }
            for val in dict.values {
                if let result = deepSearchAccountInfo(in: val) {
                    return result
                }
            }
        } else if let arr = value as? [Any] {
            for item in arr {
                if let result = deepSearchAccountInfo(in: item) {
                    return result
                }
            }
        }
        return nil
    }

    static func parseAccountSectionList(
        _ asl: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        guard let items = asl["items"] as? [[String: Any]] else {
            return nil
        }
        for item in items {
            if let result = extractAccountNameAndPhoto(from: item) {
                return result
            }
        }
        return nil
    }

    static func extractAccountNameAndPhoto(
        from node: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        let key = "activeAccountHeaderRenderer"
        guard let renderer = node[key] as? [String: Any] else {
            return nil
        }
        let nameDict = renderer["accountName"] as? [String: Any]
        guard let name = nameDict?["simpleText"] as? String else {
            return nil
        }
        let photoDict = renderer["accountPhoto"] as? [String: Any]
        let thumbs = photoDict?["thumbnails"] as? [[String: Any]]
        let thumb = thumbs?.last?["url"] as? String
        return (name, thumb)
    }

    // MARK: Instance Methods

    func executeAccountsList(
        token: String,
        completion: @escaping (Result<(name: String, avatarURL: String?), Error>) -> Void
    ) {
        execute(
            urlString: "\(baseURL)\(InnertubeEndpoint.accountList)",
            body: tvContext,
            headers: authHeaders(token: token),
            logTag: "accountsList"
        ) { json -> (name: String, avatarURL: String?)? in
            guard let info = InnertubeClient.parseAccountsListJSON(json) else {
                Self.logUnknownAccountStructure(json)
                return nil
            }
            AppLog.innertube(
                "accountsList: name=\(info.name), avatar=\(info.avatarURL ?? "nil")"
            )
            return info
        } completion: { completion($0) }
    }
}

// MARK: - Private Account Helpers

private extension InnertubeClient {
    static func parseHeaderAccount(
        _ json: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        let header = json["header"] as? [String: Any]
        let key = "activeAccountHeaderRenderer"
        guard let renderer = header?[key] as? [String: Any],
              let nameDict = renderer["accountName"] as? [String: Any],
              let name = nameDict["simpleText"] as? String
        else {
            return nil
        }
        let photoDict = renderer["accountPhoto"] as? [String: Any]
        let thumbs = photoDict?["thumbnails"] as? [[String: Any]]
        let thumb = thumbs?.last?["url"] as? String
        return (name, thumb)
    }

    static func parseAccountSections(
        _ json: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        guard let sections = json["contents"] as? [[String: Any]] else {
            return nil
        }
        for section in sections {
            if let result = parseAccountSection(section) {
                return result
            }
        }
        return nil
    }

    static func parseAccountSection(
        _ section: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        let key = "accountSectionListRenderer"
        guard let aslr = section[key] as? [String: Any],
              let innerSections = aslr["contents"] as? [[String: Any]]
        else {
            return nil
        }
        for inner in innerSections {
            if let result = parseAccountItems(inner) {
                return result
            }
        }
        return nil
    }

    static func parseAccountItems(
        _ inner: [String: Any]
    ) -> (name: String, avatarURL: String?)? {
        let key = "accountItemSectionRenderer"
        guard let aisr = inner[key] as? [String: Any],
              let items = aisr["contents"] as? [[String: Any]]
        else {
            return nil
        }
        for item in items {
            guard let ai = item["accountItem"] as? [String: Any] else {
                continue
            }
            let nameDict = ai["accountName"] as? [String: Any]
            let bylineDict = ai["accountByline"] as? [String: Any]
            let name = nameDict?["simpleText"] as? String
                ?? bylineDict?["simpleText"] as? String
                ?? ""
            let photoDict = ai["accountPhoto"] as? [String: Any]
            let thumb = photoDict.flatMap {
                ($0["thumbnails"] as? [[String: Any]])?.last?["url"] as? String
            }
            if !name.isEmpty {
                return (name, thumb)
            }
        }
        return nil
    }

    static func logUnknownAccountStructure(
        _ json: [String: Any]
    ) {
        if let pretty = try? JSONSerialization.data(
            withJSONObject: json,
            options: .prettyPrinted
        ),
            let str = String(data: pretty, encoding: .utf8) {
            AppLog.innertube(
                "accountsList unknown structure:\n\(str.prefix(3_000))"
            )
        }
    }
}
