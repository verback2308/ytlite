import UIKit

// MARK: - Comments
extension WatchViewController {
    func resetComments() {
        comments = []
        commentsContinuation = nil
        visibleCommentsCount = commentsPageSize
        isLoadingComments = false
        commentsLabel.text = "Comments"
        renderComments()
    }

    func loadComments(continuation: String? = nil) {
        guard !isLoadingComments else {
            return
        }
        isLoadingComments = true
        loadMoreCommentsButton.isEnabled = false
        loadMoreCommentsButton.isHidden = comments.isEmpty
        loadMoreCommentsButton.setTitle(
            "Loading comments...",
            for: .normal
        )
        if comments.isEmpty {
            commentsLabel.text = "Loading comments..."
            renderComments()
        }
        client.fetchComments(
            videoId: initialVideo.id,
            continuation: continuation,
            cancellationToken: pageLoadToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                self?.handleCommentsResult(
                    result,
                    continuation: continuation
                )
            }
        }
    }

    func handleCommentsResult(
        _ result: Result<CommentsPage, Error>,
        continuation: String?
    ) {
        isLoadingComments = false
        switch result {
        case .failure(let error):
            AppLog.player(
                "comments load failed "
                + "\(initialVideo.id): \(error)"
            )
            if comments.isEmpty {
                commentsLabel.text = "Comments unavailable"
            }
        case .success(let page):
            commentsContinuation = page.continuation
            if continuation == nil {
                comments = page.comments
            } else {
                appendNewComments(page.comments)
            }
            commentsLabel.text = page.title
                ?? "Comments (\(comments.count))"
        }
        renderComments()
    }

    func appendNewComments(_ newComments: [Comment]) {
        let existingIds = Set(comments.map(\.id))
        let unique = newComments.filter {
            !existingIds.contains($0.id)
        }
        comments.append(contentsOf: unique)
    }

    func renderComments() {
        commentsStackView.arrangedSubviews.forEach { vw in
            commentsStackView.removeArrangedSubview(vw)
            vw.removeFromSuperview()
        }
        if comments.isEmpty {
            renderEmptyComments()
        } else {
            for comment in comments.prefix(
                visibleCommentsCount
            ) {
                commentsStackView.addArrangedSubview(
                    makeCommentView(comment)
                )
            }
        }
        updateLoadMoreButton()
        view.setNeedsLayout()
    }

    func renderEmptyComments() {
        let emptyLabel = UILabel()
        emptyLabel.numberOfLines = 0
        emptyLabel.font = UIFont.systemFont(ofSize: 13)
        emptyLabel.textColor =
            ThemeManager.shared.secondaryText
        emptyLabel.text = isLoadingComments
            ? "Loading comments..."
            : "Comments are unavailable yet."
        commentsStackView.addArrangedSubview(emptyLabel)
    }

    func updateLoadMoreButton() {
        let hasMore = visibleCommentsCount < comments.count
        let hasCont = commentsContinuation != nil
        loadMoreCommentsButton.isHidden =
            !hasMore && !hasCont
        if isLoadingComments {
            loadMoreCommentsButton.setTitle(
                "Loading comments...",
                for: .normal
            )
            loadMoreCommentsButton.isEnabled = false
        } else {
            loadMoreCommentsButton.setTitle(
                "Load more comments",
                for: .normal
            )
            loadMoreCommentsButton.isEnabled = true
        }
    }

    func makeCommentView(
        _ comment: Comment
    ) -> UIView {
        CommentViewBuilder.makeCommentView(comment)
    }

    func expandRelatedIfNeeded() {
        guard visibleRelatedVideos.count
                < allRelatedVideos.count else {
            return
        }
        let nextCount = min(
            visibleRelatedVideos.count + relatedBatchSize,
            allRelatedVideos.count
        )
        visibleRelatedVideos = Array(
            allRelatedVideos.prefix(nextCount)
        )
        relatedCollectionView.reloadData()
        view.setNeedsLayout()
    }

    func expandCommentsIfNeeded() {
        if visibleCommentsCount < comments.count {
            visibleCommentsCount += commentsPageSize
            renderComments()
        } else if commentsContinuation != nil,
                  !isLoadingComments {
            loadComments(continuation: commentsContinuation)
        }
    }
}
