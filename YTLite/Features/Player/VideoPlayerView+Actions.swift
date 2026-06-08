import AVFoundation
import AVKit
import UIKit

// MARK: - Gesture Handling

extension VideoPlayerView {
    @objc
    func handleTap() {
        if controlsVisible {
            setControls(visible: false, animated: true)
        } else {
            setControls(visible: true, animated: true)
            scheduleAutoHide()
        }
    }

    @objc
    func handleDoubleTap(
        _ gesture: UITapGestureRecognizer
    ) {
        let xPosition = gesture.location(in: self).x
        if xPosition < bounds.width / 2 {
            rewindTapped()
        } else {
            forwardTapped()
        }
        if !controlsVisible {
            setControls(visible: true, animated: true)
        }
        scheduleAutoHide()
    }

    @objc
    func handlePinch(
        _ gesture: UIPinchGestureRecognizer
    ) {
        guard gesture.state == .ended else {
            return
        }
        if gesture.scale > 1.2, !isFullscreen {
            delegate?.videoPlayerViewDidTapFullscreen(self)
        } else if gesture.scale < 0.8, isFullscreen {
            delegate?.videoPlayerViewDidTapFullscreen(self)
        }
    }

    @objc
    func handleSwipeDown() {
        guard isFullscreen else {
            return
        }
        delegate?.videoPlayerViewDidTapFullscreen(self)
    }
}

// MARK: - Controls Visibility

extension VideoPlayerView {
    func setControls(visible: Bool, animated: Bool) {
        controlsVisible = visible
        let targetAlpha: CGFloat = visible ? 1 : 0
        let animDuration = animated ? 0.2 : 0
        UIView.animate(withDuration: animDuration) {
            self.controlsView.alpha = targetAlpha
            self.topGradientLayer.opacity = visible
                ? 1
                : 0
            self.bottomGradientLayer.opacity = visible
                ? 1
                : 0
        }
    }

    func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.player?.rate ?? 0 > 0
            else {
                return
            }
            self.setControls(
                visible: false,
                animated: true
            )
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 3,
            execute: item
        )
    }

    func pauseAutoHide() {
        hideWorkItem?.cancel()
    }
}

// MARK: - Button Actions

extension VideoPlayerView {
    @objc
    func playPauseTapped() {
        guard let player else {
            return
        }
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
        scheduleAutoHide()
    }

    @objc
    func rewindTapped() {
        guard let player else {
            return
        }
        let offset = CMTime(
            seconds: 10,
            preferredTimescale: 600
        )
        let newTime = max(
            player.currentTime() - offset,
            .zero
        )
        player.seek(
            to: newTime,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        scheduleAutoHide()
    }

    @objc
    func forwardTapped() {
        guard let player else {
            return
        }
        let offset = CMTime(
            seconds: 10,
            preferredTimescale: 600
        )
        let newTime = player.currentTime() + offset
        player.seek(
            to: newTime,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        scheduleAutoHide()
    }

    @objc
    func skipButtonTapped() {
        onSkipTapped?()
    }

    @objc
    func settingsTapped() {
        delegate?.videoPlayerViewDidTapSettings(self)
        scheduleAutoHide()
    }

    @objc
    func fullscreenTapped() {
        delegate?.videoPlayerViewDidTapFullscreen(self)
    }
}

// MARK: - Icon Updates

extension VideoPlayerView {
    func updatePlayPauseIcon() {
        let isPlaying = (player?.rate ?? 0) > 0
        let icon = isPlaying
            ? PlayerIcons.pause()
            : PlayerIcons.play()
        playPauseButton.setImage(icon, for: .normal)
    }

    func updateFullscreenIcon() {
        fullscreenButton.setImage(
            PlayerIcons.fullscreen(
                isFullscreen: isFullscreen
            ),
            for: .normal
        )
    }

    func setCenter(hidden: Bool) {
        playPauseButton.isHidden = hidden
        rewindButton.isHidden = hidden
        forwardButton.isHidden = hidden
    }

    func setupPiP() {
        let supported = AVPictureInPictureController
            .isPictureInPictureSupported()
        guard supported else {
            return
        }
        pipController = AVPictureInPictureController(
            playerLayer: playerLayer
        )
        pipController?.delegate = self
    }

    @objc
    func pipTapped() {
        guard let pip = pipController else {
            return
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }
}

// MARK: - PiP Delegate

extension VideoPlayerView: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        pipButton.setImage(
            PlayerIcons.pipExit(),
            for: .normal
        )
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ controller: AVPictureInPictureController
    ) {
        pipButton.setImage(
            PlayerIcons.pip(),
            for: .normal
        )
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
            completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
