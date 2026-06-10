// swiftlint:disable file_length
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
        prefetchNextVideoPoToken(page)
    }

    // Warm up PoToken for autoplay next video while current is playing
    private func prefetchNextVideoPoToken(_ page: WatchPage) {
        guard let nextId = page.nextVideo?.id else {
            return
        }
        WebPoTokenService.shared.fetchSessionToken(
            identifier: nextId
        ) { _ in }
    }

    func applyChannelInfo(from page: WatchPage) {
        guard let channelInfo = page.channelInfo else {
            let chId = page.video.channelId ?? "nil"
            AppLog.channel(
                "applyChannelInfo: no channelInfo,"
                + " videoChannelId=\(chId)"
            )
            if let chId = page.video.channelId {
                fetchChannelAvatar(channelId: chId)
            }
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
            AppLog.channel("applyChannelInfo: avatarURL nil, fetching for \(chId)")
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
        relatedCollectionView.reloadData()
        channelInfoStore.preload(
            channelIds: related.compactMap(\.channelId)
        )
    }

    private func enrichWithChannelId(
        _ video: Video,
        from pool: [Video]
    ) -> Video {
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
        resetPlaybackSurfaces()
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
        likeCountLabel.text = "—"
        dislikeCountLabel.text = "—"
        currentLikeStatus = .indifferent
        sponsorBlock.reset()
        commentsStackView.arrangedSubviews
            .forEach { $0.removeFromSuperview() }
        loadMoreCommentsButton.isHidden = true
    }
}
