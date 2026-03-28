import Foundation

extension InnertubeClient {
    static func collectCommentThreads(
        in value: Any
    ) -> [[String: Any]] {
        var result: [[String: Any]] = []
        if let dict = value as? [String: Any] {
            if let renderer = dict[
                "commentThreadRenderer"
            ] as? [String: Any] {
                result.append(renderer)
            } else if dict["commentViewModel"]
                is [String: Any] {
                result.append(dict)
            }
            for child in dict.values {
                result.append(
                    contentsOf: collectCommentThreads(
                        in: child
                    )
                )
            }
        } else if let array = value as? [Any] {
            for child in array {
                result.append(
                    contentsOf: collectCommentThreads(
                        in: child
                    )
                )
            }
        }
        return result
    }

    static func parseComment(
        from thread: [String: Any],
        mutations: [[String: Any]]
    ) -> Comment? {
        guard let viewModel = thread[
            "commentViewModel"
        ] as? [String: Any]
        else {
            return nil
        }
        guard let commentId = viewModel["commentId"]
            as? String
        else {
            return nil
        }
        return buildComment(
            commentId: commentId,
            viewModel: viewModel,
            thread: thread,
            mutations: mutations
        )
    }

    static func attributedText(
        from value: Any?
    ) -> String? {
        guard let dict = value as? [String: Any]
        else {
            return nil
        }
        if let content = dict["content"] as? String,
           !content.isEmpty {
            return content
        }
        return simpleText(from: value)
    }

    static func findCommentsContinuation(
        in value: Any
    ) -> String? {
        if let dict = value as? [String: Any] {
            if let token = continuationToken(from: dict) {
                return token
            }
            for child in dict.values {
                if let token = findCommentsContinuation(
                    in: child
                ) {
                    return token
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let token = findCommentsContinuation(
                    in: child
                ) {
                    return token
                }
            }
        }
        return nil
    }

    static func findCommentsTitle(
        in value: Any
    ) -> String? {
        if let dict = value as? [String: Any] {
            if let title = commentsTitleFromDict(dict) {
                return title
            }
            for child in dict.values {
                if let title = findCommentsTitle(
                    in: child
                ) {
                    return title
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let title = findCommentsTitle(
                    in: child
                ) {
                    return title
                }
            }
        }
        return nil
    }
}

private extension InnertubeClient {
    static func continuationToken(
        from dict: [String: Any]
    ) -> String? {
        guard let renderer = dict[
            "continuationItemRenderer"
        ] as? [String: Any]
        else {
            return nil
        }
        let endpoint = renderer[
            "continuationEndpoint"
        ] as? [String: Any]
        let command = endpoint?[
            "continuationCommand"
        ] as? [String: Any]
        guard let token = command?["token"] as? String,
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    static func commentsTitleFromDict(
        _ dict: [String: Any]
    ) -> String? {
        if let renderer = dict[
            "commentsHeaderRenderer"
        ] as? [String: Any] {
            return simpleText(
                from: renderer["countText"]
            ) ?? simpleText(
                from: renderer["commentsCount"]
            ) ?? simpleText(
                from: renderer["titleText"]
            )
        }
        if let renderer = dict[
            "commentsEntryPointHeaderRenderer"
        ] as? [String: Any] {
            return simpleText(
                from: renderer["commentCount"]
            ) ?? simpleText(
                from: renderer["headerText"]
            )
        }
        return nil
    }
}
