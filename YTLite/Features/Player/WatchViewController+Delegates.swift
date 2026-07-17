import UIKit

// MARK: - VideoPlayerViewDelegate

extension WatchViewController: VideoPlayerViewDelegate {
    func videoPlayerViewDidTapSettings(
        _ playerView: VideoPlayerView
    ) {
        presentPlayerMenu(
            title: "Playback settings",
            items: [
                PlayerMenuItem(title: "Quality") { [weak self] in
                    self?.showQualityPicker()
                }
            ]
        )
    }

    func videoPlayerViewDidTapFullscreen(_ playerView: VideoPlayerView) {
        if playerView.isFullscreen {
            exitFullscreen(playerView: playerView)
            return
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            enterFullscreen(playerView: playerView)
        } else {
            let orientation = UIDevice.current.orientation
            let landscape: UIDeviceOrientation = orientation.isLandscape
                ? orientation : .landscapeLeft
            enterLandscapeFullscreen(
                playerView: playerView,
                orientation: landscape
            )
        }
    }

    func enterFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window else {
            return
        }
        let frameInWindow = playerView.convert(
            playerView.bounds, to: window
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
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = window.bounds
            },
            completion: { _ in
                playerView.applyAutoZoomIfNeeded()
            }
        )
    }

    func exitFullscreen(playerView: VideoPlayerView) {
        guard let window = view.window,
              let snap = fullscreenSnapshot else {
            return
        }
        let target = snap.superview.convert(snap.frame, to: window)
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.frame = target
            }, completion: { [weak self] _ in
                self?.restoreFromFullscreen(playerView: playerView, snapshot: snap)
            }
        )
    }

    func restoreFromFullscreen(
        playerView: VideoPlayerView,
        snapshot: (superview: UIView, frame: CGRect)
    ) {
        playerView.removeFromSuperview()
        let sv = snapshot.superview
        playerView.transform = .identity
        playerView.bounds = CGRect(origin: .zero, size: snapshot.frame.size)
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.autoresizingMask = []
        sv.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: sv.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: sv.bottomAnchor)
        ])
        playerView.isFullscreen = false
        isLandscapeFullscreen = false
        fullscreenSnapshot = nil
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        updateLayoutForSize()
    }
}

// MARK: - Status bar / home indicator

extension WatchViewController {
    static var hidesStatusBarInFullscreen: Bool {
        UserDefaults.standard.object(
            forKey: UserDefaultsKeys.Player.hideStatusBarInFullscreen
        ) as? Bool ?? true
    }

    /// Fullscreen via either path — iPhone transform-based landscape or the
    /// iPad window-fill (`enterFullscreen`).
    var isPlayerFullscreen: Bool {
        isLandscapeFullscreen || videoPlayerView?.isFullscreen == true
    }

    override var prefersStatusBarHidden: Bool {
        isPlayerFullscreen && Self.hidesStatusBarInFullscreen
    }

    /// Over fullscreen video the bar must be light regardless of theme —
    /// `.default` is black-on-black there (looks "hidden", except a charging
    /// battery icon).
    override var preferredStatusBarStyle: UIStatusBarStyle {
        isPlayerFullscreen ? .lightContent : ThemeManager.shared.statusBarStyle
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        isPlayerFullscreen
    }
}

// MARK: - iPhone landscape fullscreen (no UI rotation)
extension WatchViewController {
    func enterLandscapeFullscreen(
        playerView: VideoPlayerView,
        orientation: UIDeviceOrientation
    ) {
        guard let window = view.window else {
            return
        }
        let frameInWindow = playerView.convert(playerView.bounds, to: window)
        if fullscreenSnapshot == nil {
            fullscreenSnapshot = (
                superview: playerView.superview ?? view,
                frame: playerView.frame
            )
        }
        isLandscapeFullscreen = true
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        playerView.removeFromSuperview()
        playerView.translatesAutoresizingMaskIntoConstraints = true
        playerView.autoresizingMask = []
        playerView.frame = frameInWindow
        window.addSubview(playerView)
        playerView.isFullscreen = true
        // Rotate clockwise for landscapeLeft, counterclockwise for landscapeRight,
        // so the video appears right-side-up from the user's perspective.
        let angle: CGFloat = orientation == .landscapeLeft ? .pi / 2 : -.pi / 2
        animateLandscapeEntry(playerView: playerView, window: window, angle: angle)
    }

    private func animateLandscapeEntry(
        playerView: VideoPlayerView,
        window: UIWindow,
        angle: CGFloat
    ) {
        let width = window.bounds.width
        let height = window.bounds.height
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            options: .curveEaseInOut,
            animations: {
                playerView.transform = CGAffineTransform(rotationAngle: angle)
                playerView.bounds = CGRect(x: 0, y: 0, width: height, height: width)
                playerView.center = CGPoint(x: width / 2, y: height / 2)
            },
            completion: { _ in
                playerView.applyAutoZoomIfNeeded()
            }
        )
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
                playerView.bounds = CGRect(
                    origin: .zero,
                    size: target.size
                )
                playerView.center = CGPoint(
                    x: target.midX,
                    y: target.midY
                )
            },
            completion: { [weak self] _ in
                self?.restoreFromFullscreen(playerView: playerView, snapshot: snap)
            }
        )
    }
}
