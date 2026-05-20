import UIKit

// MARK: - Like / Dislike / Subscribe
extension WatchViewController {
    @objc
    func likeTapped() {
        guard let videoId = watchPage?.video.id else {
            return
        }
        let wasLiked = currentLikeStatus == .like
        currentLikeStatus = wasLiked ? .indifferent : .like
        AppLog.player(
            "like tapped: "
            + "\(wasLiked ? "removing" : "sending") like"
            + " for \(videoId)"
        )
        updateLikeDislikeUI()
        if wasLiked {
            engagementClient.removeLike(videoId: videoId) { [weak self] result in
                self?.handleLikeToggleResult(result, videoId: videoId, wasLiked: true)
            }
        } else {
            engagementClient.sendLike(videoId: videoId) { [weak self] result in
                self?.handleLikeToggleResult(result, videoId: videoId, wasLiked: false)
            }
        }
    }

    @objc
    func dislikeTapped() {
        guard let videoId = watchPage?.video.id else {
            return
        }
        let wasDisliked = currentLikeStatus == .dislike
        currentLikeStatus = wasDisliked ? .indifferent : .dislike
        AppLog.player(
            "like tapped: "
            + "\(wasDisliked ? "removing" : "sending")"
            + " dislike for \(videoId)"
        )
        updateLikeDislikeUI()
        if wasDisliked {
            engagementClient.removeLike(videoId: videoId) { [weak self] result in
                self?.handleDislikeToggleResult(result, videoId: videoId, wasDisliked: true)
            }
        } else {
            engagementClient.sendDislike(videoId: videoId) { [weak self] result in
                self?.handleDislikeToggleResult(result, videoId: videoId, wasDisliked: false)
            }
        }
    }

    // MARK: - Subscribe

    func handleSubscribeResult(
        _ result: Result<Void, Error>,
        channelId: String,
        wasSubscribed: Bool
    ) {
        subscribeButton.isEnabled = true
        switch result {
        case .success:
            let verb = wasSubscribed
                ? "unsubscribed" : "subscribed"
            AppLog.subscribe(
                "\(verb) channelId=\(channelId)"
            )
        case .failure(let error):
            let verb = wasSubscribed
                ? "unsubscribe" : "subscribe"
            AppLog.subscribe(
                "\(verb) failed channelId=\(channelId): \(error)"
            )
            isSubscribed = wasSubscribed
            subscribeButton.setTitle(
                wasSubscribed ? "Subscribed" : "Subscribe",
                for: .normal
            )
            applyTheme()
        }
    }

    @objc
    func subscribeButtonTapped() {
        guard let channelId = watchPage?.channelInfo?.id
            ?? watchPage?.video.channelId else {
            return
        }
        let wasSubscribed = isSubscribed
        isSubscribed = !wasSubscribed
        subscribeButton.setTitle(
            isSubscribed ? "Subscribed" : "Subscribe",
            for: .normal
        )
        subscribeButton.isEnabled = false
        applyTheme()
        let handler: (Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                self?.handleSubscribeResult(
                    result,
                    channelId: channelId,
                    wasSubscribed: wasSubscribed
                )
            }
        }
        if wasSubscribed {
            engagementClient.unsubscribeFromChannel(channelId: channelId, completion: handler)
        } else {
            engagementClient.subscribeToChannel(channelId: channelId, completion: handler)
        }
    }

    // MARK: - Share & Navigation

    @objc
    func shareTapped() {
        let videoId = watchPage?.video.id ?? initialVideo.id
        guard let url = URL(string: "https://youtu.be/\(videoId)") else {
            return
        }
        let ac = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        if let popover = ac.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(ac, animated: true)
    }

    @objc
    func openChannel() {
        let sourceVideo = watchPage?.video ?? initialVideo
        guard let channelId = sourceVideo.channelId else {
            return
        }
        navigationController?.pushViewController(
            channelViewControllerFactory(
                channelId,
                sourceVideo.channelName
            ),
            animated: true
        )
    }

    @objc
    func loadMoreCommentsTapped() {
        if visibleCommentsCount < comments.count {
            visibleCommentsCount += commentsPageSize
            renderComments()
        } else if let continuation = commentsContinuation {
            loadComments(continuation: continuation)
        }
    }

    @objc
    func closeTapped() {
        exitFullscreenIfNeeded()
        videoRouter.minimize()
    }

    func exitFullscreenIfNeeded() {
        guard fullscreenSnapshot != nil,
              let playerView = videoPlayerView else {
            return
        }
        exitFullscreen(playerView: playerView)
    }
}
