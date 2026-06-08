import Foundation

extension InnertubeClient {
    static func parseChannelInfo(
        _ json: [String: Any],
        fallbackChannelId: String
    ) -> ChannelInfo? {
        let fid = fallbackChannelId
        let result = parsePageHeaderChannel(
            json, fallbackId: fid
        )
            ?? parseC4ChannelHeader(json, fallbackId: fid)
            ?? parseLockupChannel(json, fallbackId: fid)
            ?? parseMetadataChannel(json, fallbackId: fid)
            ?? parseHeuristicChannel(
                json, fallbackId: fid
            )
        if result == nil {
            logChannelFailure(json, channelId: fid)
        }
        return result
    }
}

private extension InnertubeClient {
    static func parsePageHeaderChannel(
        _ json: [String: Any],
        fallbackId: String
    ) -> ChannelInfo? {
        guard let pageHeader = firstRenderer(
            in: json,
            named: "pageHeaderRenderer"
        )
        else {
            return nil
        }
        let content = pageHeader["content"]
            as? [String: Any]
        guard let vm = content?[
            "pageHeaderViewModel"
        ] as? [String: Any]
        else {
            return nil
        }
        var fields = ChannelFields(
            id: pageHeaderChannelId(
                json, fallback: fallbackId
            ),
            title: pageHeaderTitle(vm),
            avatarURL: pageHeaderAvatar(vm)
        )
        fields.isVerified = pageHeaderVerified(vm)
        fields.bannerURL = pageHeaderBanner(vm)
        let meta = pageHeaderMeta(vm)
        fields.subscriberCountText = meta.subCount
        fields.videoCountText = meta.videoCount
        fields.desc = pageHeaderDesc(vm, json: json)
        fields.contactInfo = pageHeaderContact(vm)
        return buildChannelInfo(fields)
    }

    static func pageHeaderTitle(
        _ vm: [String: Any]
    ) -> String {
        let dynText = (vm["title"]
            as? [String: Any])?[
            "dynamicTextViewModel"
        ] as? [String: Any]
        let text = dynText?["text"] as? [String: Any]
        return text?["content"] as? String ?? ""
    }

    static func pageHeaderVerified(
        _ vm: [String: Any]
    ) -> Bool {
        let titleDict = vm["title"] as? [String: Any]
        let dynText = titleDict?[
            "dynamicTextViewModel"
        ] as? [String: Any]
        let textDict = dynText?["text"]
            as? [String: Any]
        let runs = textDict?["attachmentRuns"]
            as? [[String: Any]] ?? []
        return runs.contains {
            isVerifiedBadgeRun($0)
        }
    }

    static func isVerifiedBadgeRun(
        _ run: [String: Any]
    ) -> Bool {
        let name = run["element"]
            .flatMap {
                ($0 as? [String: Any])?["type"]
            }
            .flatMap {
                ($0 as? [String: Any])?["imageType"]
            }
            .flatMap {
                ($0 as? [String: Any])?["image"]
            }
            .flatMap {
                ($0 as? [String: Any])?["sources"]
            }
            .flatMap {
                ($0 as? [[String: Any]])?.first
            }
            .flatMap {
                $0["clientResource"] as? [String: Any]
            }
            .flatMap {
                $0["imageName"] as? String
            }
        return name == "CHECK_CIRCLE_FILLED"
            || name == "OFFICIAL_ARTIST_BADGE"
    }

    static func pageHeaderAvatar(
        _ vm: [String: Any]
    ) -> String? {
        (vm["image"] as? [String: Any])
            .flatMap {
                $0["decoratedAvatarViewModel"]
                    as? [String: Any]
            }
            .flatMap {
                $0["avatar"] as? [String: Any]
            }
            .flatMap {
                $0["avatarViewModel"] as? [String: Any]
            }
            .flatMap {
                $0["image"] as? [String: Any]
            }
            .flatMap {
                $0["sources"] as? [[String: Any]]
            }
            .flatMap { $0.last?["url"] as? String }
    }

    static func pageHeaderBanner(
        _ vm: [String: Any]
    ) -> String? {
        (vm["banner"] as? [String: Any])
            .flatMap {
                $0["imageBannerViewModel"]
                    as? [String: Any]
            }
            .flatMap {
                $0["image"] as? [String: Any]
            }
            .flatMap {
                $0["sources"] as? [[String: Any]]
            }
            .flatMap { $0.last?["url"] as? String }
    }

    static func pageHeaderMeta(
        _ vm: [String: Any]
    ) -> (subCount: String?, videoCount: String?) {
        let rows = (vm["metadata"]
            as? [String: Any])
            .flatMap {
                $0["contentMetadataViewModel"]
                    as? [String: Any]
            }
            .flatMap {
                $0["metadataRows"]
                    as? [[String: Any]]
            } ?? []
        let parts: [String] = rows
            .flatMap {
                $0["metadataParts"]
                    as? [[String: Any]] ?? []
            }
            .compactMap {
                ($0["text"] as? [String: Any])?[
                    "content"
                ] as? String
            }
        let sub = parts.first {
            $0.lowercased().contains("subscriber")
        }
        let vid = parts.first {
            $0.lowercased().contains("video")
        }
        return (sub, vid)
    }

    static func pageHeaderDesc(
        _ vm: [String: Any],
        json: [String: Any]
    ) -> String? {
        let vmDesc = (vm["description"]
            as? [String: Any])
            .flatMap {
                $0["descriptionPreviewViewModel"]
                    as? [String: Any]
            }
            .flatMap {
                $0["description"] as? [String: Any]
            }
            .flatMap { $0["content"] as? String }
            .flatMap { $0.isEmpty ? nil : $0 }
        if let vmDesc {
            return vmDesc
        }
        let meta = firstRenderer(
            in: json,
            named: "channelMetadataRenderer"
        )
        return (meta?["description"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func pageHeaderContact(
        _ vm: [String: Any]
    ) -> String? {
        (vm["attribution"] as? [String: Any])
            .flatMap {
                $0["attributionViewModel"]
                    as? [String: Any]
            }
            .flatMap {
                $0["text"] as? [String: Any]
            }
            .flatMap { $0["content"] as? String }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    static func pageHeaderChannelId(
        _ json: [String: Any],
        fallback: String
    ) -> String {
        let meta = firstRenderer(
            in: json,
            named: "channelMetadataRenderer"
        )
        return meta?["externalId"] as? String
            ?? fallback
    }
}
