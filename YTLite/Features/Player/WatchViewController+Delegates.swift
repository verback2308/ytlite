import UIKit

// MARK: - VideoPlayerViewDelegate

extension WatchViewController: VideoPlayerViewDelegate {
    func videoPlayerViewDidTapSettings(
        _ playerView: VideoPlayerView
    ) {
        let alert = UIAlertController(
            title: "Playback settings",
            message: nil,
            preferredStyle: .actionSheet
        )
        alert.addAction(
            UIAlertAction(
                title: "Quality",
                style: .default
            ) { [weak self] _ in
                self?.showQualityPicker()
            }
        )
        alert.addAction(
            UIAlertAction(title: "Cancel", style: .cancel)
        )
        configurePopover(
            for: alert,
            sourceView: playerView
        )
        present(alert, animated: true)
    }

    func videoPlayerViewDidTapFullscreen(
        _ playerView: VideoPlayerView
    ) {
        if playerView.isFullscreen {
            exitFullscreen(playerView: playerView)
        } else {
            enterFullscreen(playerView: playerView)
        }
    }

    func enterFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window else {
            return
        }
        let frameInWindow = playerView.convert(
            playerView.bounds,
            to: window
        )
        fullscreenSnapshot = (
            superview: playerView.superview ?? view,
            frame: playerView.frame
        )
        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = true
        // Allow the player to resize with the window when the device rotates while
        // in fullscreen, so the video fills the screen in the new orientation.
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.frame = frameInWindow
        window.addSubview(playerView)
        playerView.isFullscreen = true
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut
        ) {
            playerView.frame = window.bounds
        }
    }

    func exitFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window,
              let snap = fullscreenSnapshot else {
            return
        }
        let target = snap.superview.convert(
            snap.frame,
            to: window
        )
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = target
            },
            completion: { [weak self] _ in
                self?.restoreFromFullscreen(
                    playerView: playerView,
                    snapshot: snap
                )
            }
        )
    }

    func restoreFromFullscreen(
        playerView: VideoPlayerView,
        snapshot: (superview: UIView, frame: CGRect)
    ) {
        playerView.removeFromSuperview()
        let sv = snapshot.superview
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.autoresizingMask = []
        sv.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(
                equalTo: sv.leadingAnchor
            ),
            playerView.trailingAnchor.constraint(
                equalTo: sv.trailingAnchor
            ),
            playerView.topAnchor.constraint(
                equalTo: sv.topAnchor
            ),
            playerView.bottomAnchor.constraint(
                equalTo: sv.bottomAnchor
            )
        ])
        playerView.isFullscreen = false
        fullscreenSnapshot = nil
        // Re-run layout so all content (metaLabel, related list, etc.) reflows
        // correctly for the current orientation after exiting fullscreen.
        updateLayoutForSize()
    }

    func showQualityPicker() {
        guard let info = playbackFacade.activePlaybackInfo,
              let audioFormat = info.dashAudioFormat else {
            return
        }
        let formats = info.allDashVideoFormats
        guard !formats.isEmpty else {
            return
        }
        let alert = UIAlertController(
            title: "Quality",
            message: nil,
            preferredStyle: .actionSheet
        )
        for format in formats {
            addQualityAction(
                to: alert,
                format: format,
                audioFormat: audioFormat
            )
        }
        alert.addAction(
            UIAlertAction(title: "Cancel", style: .cancel)
        )
        configurePopover(
            for: alert,
            sourceView: videoPlayerView
        )
        present(alert, animated: true)
    }

    func addQualityAction(
        to alert: UIAlertController,
        format: DashFormatInfo,
        audioFormat: DashFormatInfo
    ) {
        let label = qualityLabel(for: format)
        let active = playbackFacade.activeVideoFormat
        let isCurrent = format.itag == active?.itag
        let title = isCurrent ? "✓ \(label)" : label
        alert.addAction(
            UIAlertAction(
                title: title,
                style: .default
            ) { [weak self] _ in
                self?.switchQuality(
                    to: format,
                    audioFormat: audioFormat,
                    label: label
                )
            }
        )
    }

    func switchQuality(
        to format: DashFormatInfo,
        audioFormat: DashFormatInfo,
        label: String
    ) {
        let active = playbackFacade.activeVideoFormat
        guard format.itag != active?.itag else {
            return
        }
        let client = playbackFacade.activePlaybackClient
        let videoURL = prepareDirectPlaybackURL(
            baseURL: format.url,
            client: client,
            poToken: nil
        )
        let audioURL = prepareDirectPlaybackURL(
            baseURL: audioFormat.url,
            client: client,
            poToken: nil
        )
        playerStatusLabel.text = "Loading \(label)..."
        playerStatusLabel.isHidden = false
        buildHLSAndPlay(
            videoURL: videoURL,
            audioURL: audioURL,
            videoFormat: format,
            audioFormat: audioFormat,
            headers: playbackFacade.activePlaybackHeaders,
            quality: label
        )
    }

    func configurePopover(
        for alert: UIAlertController,
        sourceView: UIView?
    ) {
        guard let pop = alert.popoverPresentationController,
              let source = sourceView else {
            return
        }
        pop.sourceView = source
        pop.sourceRect = CGRect(
            x: source.bounds.maxX - 50,
            y: 20,
            width: 1,
            height: 1
        )
    }

    func qualityLabel(
        for format: DashFormatInfo
    ) -> String {
        guard let height = format.height else {
            return "itag \(format.itag)"
        }
        if let fps = format.fps, fps > 30 {
            return "\(height)p\(fps)"
        }
        return "\(height)p"
    }
}

// MARK: - iPhone landscape fullscreen (no UI rotation)
extension WatchViewController {
    /// Rotates the player view inside the window to fill the screen in landscape
    /// without rotating the portrait-locked UI.
    func enterLandscapeFullscreen(
        playerView: VideoPlayerView,
        orientation: UIDeviceOrientation
    ) {
        guard let window = view.window else {
            return
        }
        let frameInWindow = playerView.convert(playerView.bounds, to: window)
        fullscreenSnapshot = (superview: playerView.superview ?? view, frame: playerView.frame)
        isLandscapeFullscreen = true
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()

        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = true
        playerView.autoresizingMask = []
        playerView.frame = frameInWindow
        window.addSubview(playerView)
        playerView.isFullscreen = true
        let width = window.bounds.width
        let height = window.bounds.height
        // Rotate clockwise for landscapeLeft, counterclockwise for landscapeRight,
        // so the video appears right-side-up from the user's perspective.
        let angle: CGFloat = orientation == .landscapeLeft ? .pi / 2 : -.pi / 2
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            playerView.transform = CGAffineTransform(rotationAngle: angle)
            playerView.bounds = CGRect(x: 0, y: 0, width: height, height: width)
            playerView.center = CGPoint(x: width / 2, y: height / 2)
        }
    }

    func exitLandscapeFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window,
              let snap = fullscreenSnapshot else {
            return
        }
        isLandscapeFullscreen = false
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        let target = snap.superview.convert(snap.frame, to: window)
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.transform = .identity
                playerView.frame = target
            },
            completion: { [weak self] _ in
                self?.restoreFromFullscreen(playerView: playerView, snapshot: snap)
            }
        )
    }
}
