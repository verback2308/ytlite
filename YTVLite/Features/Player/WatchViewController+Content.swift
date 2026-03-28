import UIKit

// MARK: - Vote Formatting

private func formatVoteCount(_ count: Int) -> String {
    switch count {
    case 0..<1_000:
        return "\(count)"
    case 1_000..<1_000_000:
        return String(
            format: "%.1fK",
            Double(count) / 1_000
        )
    default:
        return String(
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
        subscribeButton.setTitle("Subscribe", for: .normal)
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
                  case .success(let info) = result,
                  let avatarStr = info.avatarURL,
                  let url = URL(string: avatarStr) else {
                return
            }
            self.channelAvatarView.setImage(url: url)
        }
    }

    func buildMetaText(
        viewCount: String?,
        publishedAt: String?
    ) -> String {
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
                case .success(let page):
                    self?.applyWatchPage(page)
                case .failure(let error):
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
        guard let channelInfo = page.channelInfo else {
            return
        }
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
    }

    func applySubscriptionState(from page: WatchPage) {
        let buttonText = page.subscribeButtonText
            ?? (page.isSubscribed
                ? "Subscribed" : "Subscribe")
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
            likeCountLabel.text = "—"
        }
        dislikeCountLabel.text = "—"
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
                        == videoId else {
                    return
                }
                if case .success(let votes) = result {
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
                        == videoId else {
                    return
                }
                if case .success(let segments) = result {
                    self.sponsorBlock.segments = segments
                    self.videoPlayerView?
                        .setSponsorSegments(segments)
                }
            }
        }
    }

    func applyRelatedVideos(from page: WatchPage) {
        allRelatedVideos = page.relatedVideos
        visibleRelatedVideos = Array(
            page.relatedVideos.prefix(relatedBatchSize)
        )
        relatedCollectionView.reloadData()
        channelInfoStore.preload(
            channelIds: page.relatedVideos
                .compactMap(\.channelId)
        )
    }
}

// MARK: - Load Video

extension WatchViewController {
    func loadVideo(_ video: Video) {
        dismissAutoplayOverlay()
        pageLoadToken.cancel()
        pageLoadToken = CancellationToken()
        resetPlaybackSurfaces()
        playbackFacade.reset()
        resetVideoState()
        scrollView.setContentOffset(.zero, animated: false)
        exitFullscreenIfNeeded()
        initialVideo = video
        loadInitialState()
        loadWatchPage()
        applyTheme()
    }

    func resetVideoState() {
        watchPage = nil
        allRelatedVideos = []
        visibleRelatedVideos = []
        comments = []
        commentsContinuation = nil
        visibleCommentsCount = commentsPageSize
        isLoadingComments = false
        descriptionExpanded = false
        likeCountLabel.text = "—"
        dislikeCountLabel.text = "—"
        currentLikeStatus = .indifferent
        sponsorBlock.reset()
        commentsStackView.arrangedSubviews
            .forEach { $0.removeFromSuperview() }
        loadMoreCommentsButton.isHidden = true
    }
}
