import UIKit

// MARK: - Engagement & Actions
extension WatchViewController {
    // MARK: - App Lifecycle

    @objc
    func appDidEnterBackground() {
        let bgEnabled = BackgroundPlaybackService.isEnabled
        AppLog.player(
            "appDidEnterBackground: bgEnabled=\(bgEnabled)"
        )
        guard bgEnabled else {
            videoPlayerView?.player?.pause()
            return
        }
        // If PiP is active, leave playerLayer connected — PiP needs it.
        let pipActive = videoPlayerView?.pipController?
            .isPictureInPictureActive == true
        if pipActive {
            return
        }
        // Disconnect the video layer so iOS doesn't pause the
        // player when rendering stops. Audio continues via
        // AVAudioSession .playback category.
        videoPlayerView?.playerLayer.player = nil
    }

    @objc
    func appWillEnterForeground() {
        AppLog.player("appWillEnterForeground")
        // Reconnect the video layer to resume rendering.
        if let player = videoPlayerView?.player {
            videoPlayerView?.playerLayer.player = player
        }
    }

    // MARK: - Theming

    @objc
    func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        scrollView.backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        relatedCollectionView.backgroundColor = theme.background
        sidebarContainer.backgroundColor = theme.background
        titleLabel.textColor = theme.primaryText
        channelNameLabel.textColor = theme.primaryText
        commentsLabel.textColor = theme.primaryText
        metaLabel.textColor = theme.secondaryText
        channelMetaLabel.textColor = theme.secondaryText
        descriptionLabel.textColor = theme.secondaryText
        likeCountLabel.textColor = theme.secondaryText
        dislikeCountLabel.textColor = theme.secondaryText
        descriptionButton.setTitleColor(theme.secondaryText, for: .normal)
        loadMoreCommentsButton.setTitleColor(
            theme.isDark ? .white : theme.accent,
            for: .normal
        )
        for btn in [likeButton, dislikeButton, shareButton, saveButton, downloadButton] {
            btn.tintColor = theme.primaryText
        }
        playerContainer.backgroundColor = .black
        playerStatusLabel.textColor = .lightGray
        applyThemeToSubscribeButton()
        if isViewLoaded, navigationController != nil {
            setupNavigationBar()
        }
        updateLikeDislikeUI()
    }

    func applyThemeToSubscribeButton() {
        let theme = ThemeManager.shared
        if subscribeButton.currentTitle == "Subscribed" {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(theme.primaryText, for: .normal)
        } else {
            subscribeButton.backgroundColor = theme.accent
            subscribeButton.setTitleColor(.white, for: .normal)
        }
    }

    // MARK: - Description

    func updateDescriptionUI() {
        let text = descriptionLabel.text ?? ""
        let hasDesc = !text.isEmpty
        descriptionLabel.isHidden = !descriptionExpanded
        channelTopToMeta?.isActive = !descriptionExpanded
        channelTopToDesc?.isActive = descriptionExpanded
        descriptionButton.isHidden = !hasDesc
        descriptionButton.setTitle(
            descriptionExpanded ? "Less" : "More",
            for: .normal
        )
        view.setNeedsLayout()
    }

    @objc
    func toggleDescription() {
        descriptionExpanded.toggle()
        updateDescriptionUI()
    }

    // MARK: - Like / Dislike

    func updateLikeDislikeUI() {
        let tint = ThemeManager.shared.primaryText
        let activeTint = ThemeManager.shared.accent
        let secondary = ThemeManager.shared.secondaryText
        likeButton.tintColor = currentLikeStatus == .like
            ? activeTint : tint
        likeCountLabel.textColor = currentLikeStatus == .like
            ? activeTint : secondary
        dislikeButton.tintColor = currentLikeStatus == .dislike
            ? activeTint : tint
        dislikeCountLabel.textColor = currentLikeStatus == .dislike
            ? activeTint : secondary
    }

    func handleLikeToggleResult(
        _ result: Result<Void, Error>,
        videoId: String,
        wasLiked: Bool
    ) {
        DispatchQueue.main.async { [weak self] in
            let label = wasLiked
                ? "removeLike" : "sendLike"
            switch result {
            case .success:
                AppLog.player("\(label) success for \(videoId)")
                let rydVal = wasLiked ? 0 : 1
                if ReturnYouTubeDislikeService.enabled {
                    ReturnYouTubeDislikeService.shared
                        .reportVote(
                            videoId: videoId,
                            value: rydVal
                        )
                }
            case .failure(let error):
                AppLog.player(
                    "\(label) failed for \(videoId): \(error)"
                )
                let revert: LikeStatus = wasLiked
                    ? .like : .indifferent
                self?.currentLikeStatus = revert
                self?.updateLikeDislikeUI()
            }
        }
    }

    func handleDislikeToggleResult(
        _ result: Result<Void, Error>,
        videoId: String,
        wasDisliked: Bool
    ) {
        DispatchQueue.main.async {
            let label = wasDisliked
                ? "removeDislike" : "sendDislike"
            switch result {
            case .success:
                AppLog.player("\(label) success for \(videoId)")
                let rydVal = wasDisliked ? 0 : -1
                if ReturnYouTubeDislikeService.enabled {
                    ReturnYouTubeDislikeService.shared
                        .reportVote(
                            videoId: videoId,
                            value: rydVal
                        )
                }
            case .failure(let error):
                AppLog.player(
                    "\(label) failed for \(videoId): \(error)"
                )
            }
        }
    }
}
