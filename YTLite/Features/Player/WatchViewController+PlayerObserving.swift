import UIKit
import AVKit

// MARK: - Player Observing
extension WatchViewController {
    func startObservingPlayerItem(_ item: AVPlayerItem) {
        statusObservation = item.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] observed, _ in
            self?.handlePlayerItemStatusChange(observed)
        }
        addPlayerNotificationObservers(for: item)
    }

    func addPlayerNotificationObservers(
        for item: AVPlayerItem
    ) {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(playerItemDidFailToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
        nc.addObserver(
            self,
            selector: #selector(playerItemNewErrorLogEntry(_:)),
            name: .AVPlayerItemNewErrorLogEntry,
            object: item
        )
        nc.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    func stopObservingPlayerItem(
        _ item: AVPlayerItem
    ) {
        let nc = NotificationCenter.default
        nc.removeObserver(
            self,
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
        nc.removeObserver(
            self,
            name: .AVPlayerItemNewErrorLogEntry,
            object: item
        )
        nc.removeObserver(
            self,
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        statusObservation?.invalidate()
        statusObservation = nil
    }

    func handlePlayerItemStatusChange(
        _ item: AVPlayerItem
    ) {
        switch item.status {
        case .readyToPlay:
            logReadyToPlay(item)
        case .failed:
            logPlaybackFailure(item)
        case .unknown:
            AppLog.player("player item status unknown")
        @unknown default:
            AppLog.player(
                "player item status unexpected"
            )
        }
    }

    func logReadyToPlay(_ item: AVPlayerItem) {
        let duration = CMTimeGetSeconds(item.duration)
        let tracks = item.tracks
            .map {
                $0.assetTrack?.mediaType.rawValue
                    ?? "?"
            }
            .joined(separator: ",")
        AppLog.player(
            "player item ready:"
                + " duration=\(duration)s"
                + " tracks=[\(tracks)]"
        )
        seekToSavedPositionIfNeeded()
        if let player = videoPlayerView?.player {
            NowPlayingService.shared.beginSession(
                player: player,
                title: initialVideo.title,
                channelName: initialVideo.channelName,
                duration: duration
            )
        }
    }

    private func seekToSavedPositionIfNeeded() {
        guard !didSeekToSavedPosition,
              let prog = WatchProgressStore.shared.progress(
                  forVideoId: initialVideo.id
              ),
              prog.shouldShow,
              let player = videoPlayerView?.player
        else {
            return
        }
        didSeekToSavedPosition = true
        let target = CMTime(
            seconds: prog.position,
            preferredTimescale: 1_000
        )
        player.seek(
            to: target,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func logPlaybackFailure(_ item: AVPlayerItem) {
        let nsError = item.error as NSError?
        let desc = item.error?.localizedDescription
            ?? "unknown"
        let domain = nsError?.domain ?? "nil"
        let code = nsError?.code ?? 0
        AppLog.player(
            "player item FAILED: \(desc)"
                + " domain=\(domain)"
                + " code=\(code)"
        )
        logUnderlyingError(nsError)
    }

    func logUnderlyingError(_ nsError: NSError?) {
        guard let underlying = nsError?
            .userInfo[NSUnderlyingErrorKey]
            as? NSError else {
            return
        }
        AppLog.player(
            "underlying error:"
                + " \(underlying.domain)"
                + " code=\(underlying.code)"
                + " \(underlying.localizedDescription)"
        )
    }

    @objc
    func playerItemDidFailToPlayToEnd(
        _ note: Notification
    ) {
        let errorKey =
            AVPlayerItemFailedToPlayToEndTimeErrorKey
        let error =
            (note.userInfo?[errorKey] as? Error)?
                .localizedDescription ?? "unknown"
        AppLog.player(
            "player item failed to end: \(error)"
        )
    }

    @objc
    func playerItemDidPlayToEnd(
        _ notification: Notification
    ) {
        guard let nextVideo =
            watchPage?.nextVideo else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.showAutoplayOverlay(for: nextVideo)
        }
    }

    @objc
    func playerItemNewErrorLogEntry(
        _ note: Notification
    ) {
        guard let item =
            note.object as? AVPlayerItem,
              let events = item.errorLog()?.events,
              let last = events.last else {
            AppLog.player(
                "player item new error log entry"
            )
            return
        }
        let domain = last.errorDomain
        let comment = last.errorComment ?? "nil"
        let uri = last.uri ?? "nil"
        AppLog.player(
            "player error log:"
                + " domain=\(domain),"
                + " code=\(last.errorStatusCode),"
                + " comment=\(comment),"
                + " uri=\(uri)"
        )
    }

    func showPlaybackError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.playerSpinner.stopAnimating()
            self?.playerStatusLabel.text =
                "Playback error: \(message)"
            self?.playerStatusLabel.textColor =
                .systemRed
        }
    }

    // MARK: - Autoplay

    func showAutoplayOverlay(for video: Video) {
        autoplayOverlay?.removeFromSuperview()
        let overlay = makeAutoplayOverlay(for: video)
        // playerView may be in the window via EITHER fullscreen path
        // (rotation-based for iPhone or tap-based for iPad/portrait).
        // Use isFullscreen to detect both cases.
        if let pv = videoPlayerView, pv.isFullscreen {
            overlay.translatesAutoresizingMaskIntoConstraints = true
            overlay.frame = pv.bounds
            overlay.autoresizingMask = [
                .flexibleWidth, .flexibleHeight
            ]
            pv.addSubview(overlay)
        } else {
            overlay
                .translatesAutoresizingMaskIntoConstraints
                = false
            playerContainer.addSubview(overlay)
            applyEdgeConstraints(overlay, to: playerContainer)
        }
        autoplayOverlay = overlay
        UIView.animate(withDuration: 0.25) {
            overlay.alpha = 1
        }
        overlay.startCountdown()
    }

    private func makeAutoplayOverlay(
        for video: Video
    ) -> AutoplayOverlayView {
        let overlay = AutoplayOverlayView(
            nextVideo: video,
            countdownSecs: 5
        )
        overlay.alpha = 0
        overlay.onPlay = { [weak self] in
            self?.dismissAutoplayOverlay()
            self?.navigateTo(video)
        }
        overlay.onCancel = { [weak self] in
            self?.dismissAutoplayOverlay()
        }
        return overlay
    }

    func applyEdgeConstraints(
        _ child: UIView,
        to parent: UIView
    ) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(
                equalTo: parent.topAnchor
            ),
            child.leadingAnchor.constraint(
                equalTo: parent.leadingAnchor
            ),
            child.trailingAnchor.constraint(
                equalTo: parent.trailingAnchor
            ),
            child.bottomAnchor.constraint(
                equalTo: parent.bottomAnchor
            )
        ])
    }

    func dismissAutoplayOverlay() {
        guard let overlay = autoplayOverlay else {
            return
        }
        autoplayOverlay = nil
        UIView.animate(
            withDuration: 0.2,
            animations: { overlay.alpha = 0 },
            completion: { _ in
                overlay.removeFromSuperview()
            }
        )
    }
}
