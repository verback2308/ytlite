// swiftlint:disable file_length
import UIKit

// MARK: - Vote Formatting

private func formatVoteCount(_ count: Int) -> String {
    switch count {
    case 0 ..< 1_000:
        "\(count)"
    case 1_000 ..< 1_000_000:
        String(
            format: "%.1fK",
            Double(count) / 1_000
        )
    default:
        String(
            format: "%.1fM",
            Double(count) / 1_000_000
        )
    }
}

// MARK: - Initial State

extension WatchViewController {
    func loadInitialState() {
        titleLabel.text = initialVideo.title
        metaLabel.text = buildMetaText(
            viewCount: initialVideo.viewCount,
            publishedAt: initialVideo.publishedAt
        )
        channelNameLabel.text = initialVideo.channelName
        channelMetaLabel.text = nil
        subscribeButton.isHidden =
            !OAuthClient.shared.isAnonymous
        subscribeButton.setTitle("订阅", for: .normal)
        descriptionLabel.text = nil
        descriptionButton.isHidden = true
        resetComments()
        loadInitialAvatar()
        startPlayback()
    }

    func loadInitialAvatar() {
        if let avatarStr = initialVideo.channelAvatarURL,
           let url = URL(string: avatarStr) {
            channelAvatarView.setImage(url: url)
        } else if let channelId = initialVideo.channelId {
            fetchChannelAvatar(channelId: channelId)
        } else {
            channelAvatarView.cancel()
        }
    }

    func fetchChannelAvatar(channelId: String) {
        channelInfoStore.fetch(
            channelId: channelId
        ) { [weak self] result in
            guard let self,
                  case let .success(info) = result,
                  let avatarStr = info.avatarURL,
                  let url = URL(string: avatarStr)
            else {
                return
            }
            channelAvatarView.setImage(url: url)
        }
    }

    func buildMetaText(
        viewCount: String?,
        publishedAt: String?
    )
        -> String {
        [
            viewCount,
            publishedAt.map(
                VideoFormatters.formatRelativeDate
            )
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }
}

// MARK: - Watch Page

extension WatchViewController {
    func loadWatchPage() {
        client.fetchWatchPage(
            video: initialVideo,
            cancellationToken: pageLoadToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case let .success(page):
                    self?.applyWatchPage(page)
                case let .failure(error):
                    AppLog.player(
                        "watch page load failed "
                            + "\(self?.initialVideo.id ?? "nil")"
                            + ": \(error)"
                    )
                }
            }
        }
    }

    func applyWatchPage(_ page: WatchPage) {
        watchPage = page
        cache.setWatchPage(page, videoId: initialVideo.id)
        title = page.video.title
        titleLabel.text = page.video.title
        metaLabel.text = buildMetaText(
            viewCount: page.video.viewCount,
            publishedAt: page.video.publishedAt
        )
        applyChannelInfo(from: page)
        applySubscriptionState(from: page)
        applyEngagementData(from: page)
        fetchExternalServiceData(
            videoId: page.video.id
        )
        applyTheme()
        applyRelatedVideos(from: page)
        resetComments()
        loadComments()
        view.setNeedsLayout()
    }

    func applyChannelInfo(from page: WatchPage) {
        if let channelInfo = page.channelInfo {
            channelNameLabel.text = channelInfo.title.isEmpty
                ? initialVideo.channelName
                : channelInfo.title
            channelMetaLabel.text = channelInfo.subscriberCountText
            if let avatarStr = channelInfo.avatarURL,
               let url = URL(string: avatarStr) {
                channelAvatarView.setImage(url: url)
            } else if let chId = page.video.channelId {
                fetchChannelAvatar(channelId: chId)
            }
            return
        }
        let name = page.video.channelName.isEmpty
            ? initialVideo.channelName
            : page.video.channelName
        channelNameLabel.text = name
        channelMetaLabel.text = nil
        if let chId = page.video.channelId {
            fetchChannelAvatar(channelId: chId)
        } else {
            channelAvatarView.cancel()
        }
    }

    func applySubscriptionState(from page: WatchPage) {
        let buttonText = page.subscribeButtonText
            ?? (page.isSubscribed
                ? "已订阅" : "订阅")
        subscribeButton.setTitle(
            buttonText,
            for: .normal
        )
        isSubscribed = page.isSubscribed
        subscribeButton.isHidden = false
        descriptionLabel.text = page.description
        descriptionExpanded = false
        updateDescriptionUI()
    }

    func applyEngagementData(from page: WatchPage) {
        if let count = page.likeCount {
            likeCountLabel.text = count
        } else {
            likeCountLabel.text = "喜欢"
        }
        dislikeCountLabel.text = "不喜欢"
        currentLikeStatus =
            page.likeStatus ?? .indifferent
        updateLikeDislikeUI()
    }

    func fetchExternalServiceData(videoId: String) {
        if ReturnYouTubeDislikeService.enabled {
            fetchRYDVotes(videoId: videoId)
        }
        if SponsorBlockService.enabled {
            fetchSponsorSegments(videoId: videoId)
        }
    }

    func fetchRYDVotes(videoId: String) {
        ReturnYouTubeDislikeService.shared.fetchVotes(
            videoId: videoId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.watchPage?.video.id
                      == videoId
                else {
                    return
                }
                if case let .success(votes) = result {
                    self.likeCountLabel.text =
                        formatVoteCount(votes.likes)
                    self.dislikeCountLabel.text =
                        formatVoteCount(votes.dislikes)
                }
            }
        }
    }

    func fetchSponsorSegments(videoId: String) {
        SponsorBlockService.shared.fetchSegments(
            videoId: videoId
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.watchPage?.video.id
                      == videoId
                else {
                    return
                }
                if case let .success(segments) = result {
                    self.sponsorBlock.segments = segments
                    self.videoPlayerView?
                        .setSponsorSegments(segments)
                }
            }
        }
    }

    func applyRelatedVideos(from page: WatchPage) {
        var related = page.relatedVideos
        if let next = page.nextVideo {
            related.removeAll { $0.id == next.id }
            let enriched = enrichWithChannelId(next, from: related)
            related.insert(enriched, at: 0)
        }
        allRelatedVideos = related
        visibleRelatedVideos = Array(
            related.prefix(relatedBatchSize)
        )
        populateQueueIfNeeded(from: page)
        relatedCollectionView.reloadData()
        channelInfoStore.preload(
            channelIds: related.compactMap(\.channelId)
        )
    }

    private func populateQueueIfNeeded(
        from page: WatchPage
    ) {
        if queue.videos.contains(
            where: { $0.id == page.video.id }
        ) {
            queue.seekTo(videoId: page.video.id)
        } else if let vids = page.playlistVideos,
                  !vids.isEmpty {
            queue.setQueue(
                vids,
                title: page.playlistTitle
            )
            queue.seekTo(videoId: page.video.id)
        } else {
            queue.clear()
        }
    }

    private func enrichWithChannelId(
        _ video: Video,
        from pool: [Video]
    )
        -> Video {
        guard video.channelId == nil
        else { return video }
        let match = pool.first {
            $0.channelId != nil
                && $0.channelName == video.channelName
        }
        guard let chId = match?.channelId
        else { return video }
        return Video(
            id: video.id,
            title: video.title,
            channelId: chId,
            channelName: video.channelName,
            channelAvatarURL: video.channelAvatarURL,
            thumbnailURL: video.thumbnailURL,
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            duration: video.duration,
            isLive: video.isLive
        )
    }
}

// MARK: - Load Video

extension WatchViewController {
    /// Fresh open from grid/search/external — clears history.
    func loadVideo(_ video: Video) {
        videoHistory.removeAll()
        loadVideoInternal(video)
        updateLeftBarButton()
    }

    /// Navigate within player (related, autoplay) — pushes current to history.
    func navigateTo(_ video: Video) {
        let current = watchPage?.video ?? initialVideo
        videoHistory.append(current)
        let inFullscreen = isLandscapeFullscreen
            || (videoPlayerView?.isFullscreen == true)
        loadVideoInternal(video, keepFullscreen: inFullscreen)
        updateLeftBarButton()
    }

    /// Go back to previous video in history stack.
    func goBack() {
        guard let previous = videoHistory.popLast()
        else { return }
        loadVideoInternal(previous)
        updateLeftBarButton()
    }

    private func loadVideoInternal(
        _ video: Video,
        keepFullscreen: Bool = false
    ) {
        dismissAutoplayOverlay()
        pageLoadToken.cancel()
        pageLoadToken = CancellationToken()
        let isBg = UIApplication.shared.applicationState != .active
        if isBg {
            savedPlayerForBackground = videoPlayerView?.player
        } else {
            resetPlaybackSurfaces()
        }
        playbackFacade.reset()
        resetVideoState()
        scrollView.setContentOffset(.zero, animated: false)
        if !keepFullscreen {
            exitFullscreenIfNeeded()
        }
        initialVideo = video
        loadInitialState()
        loadWatchPage()
        applyTheme()
    }

    func resetVideoState() {
        watchPage = nil
        allRelatedVideos = []
        visibleRelatedVideos = []
        relatedCollectionView.reloadData()
        comments = []
        commentsContinuation = nil
        visibleCommentsCount = commentsPageSize
        isLoadingComments = false
        descriptionExpanded = false
        likeCountLabel.text = "喜欢"
        dislikeCountLabel.text = "不喜欢"
        currentLikeStatus = .indifferent
        sponsorBlock.reset()
        commentsStackView.arrangedSubviews
            .forEach { $0.removeFromSuperview() }
        loadMoreCommentsButton.isHidden = true
    }
}
