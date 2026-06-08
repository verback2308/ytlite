import Foundation

extension InnertubeClient {
    static func buildCommentsContinuation(
        videoId: String,
        sortBy: Int,
        commentId: String?
    ) -> String {
        let ctx = protoMessage([
            protoString(field: 2, value: videoId)
        ])
        let idField = commentId.flatMap {
            protoString(field: 16, value: $0)
        }
        let opts = protoMessage([
            protoString(field: 4, value: videoId),
            protoInt32(field: 6, value: sortBy),
            protoInt32(field: 15, value: 2),
            idField
        ].compactMap { $0 })
        let params = protoMessage([
            protoMessage(field: 4, value: opts),
            protoString(
                field: 8, value: "comments-section"
            )
        ])
        let root = protoMessage([
            protoMessage(field: 2, value: ctx),
            protoInt32(field: 3, value: 6),
            protoMessage(field: 6, value: params)
        ])
        return percentEncode(base64URLEncoded(root))
    }

    static func buildComment(
        commentId: String,
        viewModel: [String: Any],
        thread: [String: Any],
        mutations: [[String: Any]]
    ) -> Comment? {
        let commentKey = viewModel["commentKey"]
            as? String
        let toolbarStateKey = viewModel[
            "toolbarStateKey"
        ] as? String
        let toolbarSurfaceKey = viewModel[
            "toolbarSurfaceKey"
        ] as? String
        let commentMutation = findCommentMutation(
            mutations, key: commentKey
        )
        let toolbarState = findToolbarStateMutation(
            mutations, key: toolbarStateKey
        )
        let toolbarSurface = findToolbarSurface(
            mutations, key: toolbarSurfaceKey
        )
        return assembleComment(
            commentId: commentId,
            commentMutation: commentMutation,
            toolbarState: toolbarState,
            toolbarSurface: toolbarSurface,
            viewModel: viewModel,
            thread: thread
        )
    }

    static func protoMessage(_ fields: [Data]) -> Data {
        fields.reduce(into: Data()) { $0.append($1) }
    }

    static func protoMessage(
        field: Int, value: Data
    ) -> Data {
        var data = Data()
        data.append(protoKey(
            field: field, wireType: 2
        ))
        data.append(protoVarint(value.count))
        data.append(value)
        return data
    }

    static func protoString(
        field: Int, value: String
    ) -> Data {
        protoMessage(
            field: field, value: Data(value.utf8)
        )
    }

    static func protoInt32(
        field: Int, value: Int
    ) -> Data {
        var data = Data()
        data.append(protoKey(
            field: field, wireType: 0
        ))
        data.append(protoVarint(value))
        return data
    }

    static func protoKey(
        field: Int, wireType: Int
    ) -> Data {
        protoVarint((field << 3) | wireType)
    }

    static func protoVarint(_ value: Int) -> Data {
        var data = Data()
        var current = UInt64(
            bitPattern: Int64(value)
        )
        while current >= 0x80 {
            data.append(
                UInt8(current & 0x7F | 0x80)
            )
            current >>= 7
        }
        data.append(UInt8(current))
        return data
    }

    static func percentEncode(
        _ string: String
    ) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                + "abcdefghijklmnopqrstuvwxyz"
                + "0123456789-_.!~*'()"
        )
        return string.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? string
    }

    static func base64URLEncoded(
        _ data: Data
    ) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

private extension InnertubeClient {
    static func findCommentMutation(
        _ mutations: [[String: Any]],
        key: String?
    ) -> [String: Any]? {
        mutations
            .first {
                (($0["payload"] as? [String: Any])?[
                    "commentEntityPayload"
                ] as? [String: Any])?["key"]
                    as? String == key
            }
            .flatMap {
                ($0["payload"] as? [String: Any])?[
                    "commentEntityPayload"
                ] as? [String: Any]
            }
    }

    static func findToolbarStateMutation(
        _ mutations: [[String: Any]],
        key: String?
    ) -> [String: Any]? {
        let payloadKey =
            "engagementToolbarStateEntityPayload"
        return mutations
            .first {
                (($0["payload"] as? [String: Any])?[
                    payloadKey
                ] as? [String: Any])?["key"]
                    as? String == key
            }
            .flatMap {
                ($0["payload"] as? [String: Any])?[
                    payloadKey
                ] as? [String: Any]
            }
    }

    static func findToolbarSurface(
        _ mutations: [[String: Any]],
        key: String?
    ) -> [String: Any]? {
        let payloadKey =
            "engagementToolbarSurfaceEntityPayload"
        return mutations
            .first {
                ($0["entityKey"] as? String) == key
            }
            .flatMap {
                ($0["payload"] as? [String: Any])?[
                    payloadKey
                ] as? [String: Any]
            }
    }

    // swiftlint:disable:next function_parameter_count
    static func assembleComment(
        commentId: String,
        commentMutation: [String: Any]?,
        toolbarState: [String: Any]?,
        toolbarSurface: [String: Any]?,
        viewModel: [String: Any],
        thread: [String: Any]
    ) -> Comment? {
        let author = (commentMutation?["author"] as? [String: Any]) ?? [:]
        let toolbar = (commentMutation?["toolbar"] as? [String: Any]) ?? [:]
        let properties = (commentMutation?["properties"] as? [String: Any]) ?? [:]
        let avatar = commentMutation?["avatar"] as? [String: Any]
        let content = commentContent(properties)
        let isDeleted = (toolbarState?["isDeleted"] as? Bool) == true
        let hasSurface = toolbarSurface != nil || !toolbar.isEmpty
        guard !isDeleted, !content.isEmpty || hasSurface
        else {
            return nil
        }
        return Comment(
            id: commentId,
            authorName: commentAuthorName(author),
            authorChannelId: author["channelId"]
                as? String,
            authorAvatarURL: extractThumbnailURL(
                from: avatar?["image"]
            ),
            content: content,
            publishedTime: properties[
                "publishedTime"
            ] as? String,
            likeCount: commentLikeCount(toolbar),
            replyCount: commentReplyCount(toolbar),
            isPinned: viewModel["pinnedText"] != nil
                || thread["pinnedCommentBadge"] != nil
        )
    }

    static func commentAuthorName(
        _ author: [String: Any]
    ) -> String {
        (author["displayName"] as? String)
            ?? simpleText(from: author["displayText"])
            ?? "Unknown"
    }

    static func commentContent(
        _ properties: [String: Any]
    ) -> String {
        attributedText(from: properties["content"])
            ?? simpleText(from: properties["content"])
            ?? ""
    }

    static func commentLikeCount(
        _ toolbar: [String: Any]
    ) -> String? {
        (toolbar["likeCountNotliked"] as? String)
            ?? (toolbar["likeCountLiked"] as? String)
            ?? simpleText(from: toolbar["likeCountA11y"])
    }

    static func commentReplyCount(
        _ toolbar: [String: Any]
    ) -> String? {
        (toolbar["replyCount"] as? String)
            ?? simpleText(
                from: toolbar["replyCountA11y"]
            )
    }
}
