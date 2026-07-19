import AVKit
import UIKit

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
        if applyRecoverySeekIfNeeded(item) {
            return
        }
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
        beginNowPlayingSession(duration: duration)
    }

    private func seekToSavedPositionIfNeeded() {
        guard !didSeekToSavedPosition else {
            return
        }
        didSeekToSavedPosition = true
        guard let prog = WatchProgressStore.shared
            .progress(forVideoId: initialVideo.id),
            prog.shouldShow,
            prog.fraction < 0.97
        else {
            return
        }
        seekToProgress(prog)
    }

    private func seekToProgress(
        _ prog: WatchProgress
    ) {
        guard let player = videoPlayerView?.player
        else {
            return
        }
        let dur = CMTimeGetSeconds(
            player.currentItem?.duration ?? .zero
        )
        guard dur > 0 else {
            return
        }
        let pos = prog.fraction * dur
        player.seek(
            to: CMTime(
                seconds: pos,
                preferredTimescale: 1_000
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        AppLog.player(
            "resumed at \(Int(pos))s"
                + " (\(Int(prog.fraction * 100))%)"
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
        if code == -12_660
            || domain == "CoreMediaErrorDomain" {
            hasSeenPlaybackError = true
            if !isRecoveringPlayback {
                AppLog.player(
                    "player failure — scheduling recovery"
                )
                recoverPlayback()
            }
        }
    }

    func logUnderlyingError(_ nsError: NSError?) {
        guard let underlying = nsError?
            .userInfo[NSUnderlyingErrorKey]
            as? NSError
        else {
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
        hasSeenPlaybackError = true
        if !isRecoveringPlayback {
            recoverPlayback()
        }
    }

    @objc
    func playerItemDidPlayToEnd(
        _ notification: Notification
    ) {
        // Queue playback (mix/playlist) jumps straight to the next entry —
        // the countdown overlay is suggestion-autoplay only. The queue is
        // peeked, not advanced: navigation syncs it via seekTo.
        if let next = queue.nextVideo {
            AppLog.player("playToEnd: queue next=\(next.id)")
            DispatchQueue.main.async { [weak self] in
                self?.navigateTo(next)
            }
            return
        }
        guard let nextVideo = watchPage?.nextVideo else {
            AppLog.player("playToEnd: no next video")
            return
        }
        // applicationState is main-thread-only and this notification can
        // arrive off-main — read it inside the hop.
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let active = UIApplication.shared.applicationState == .active
            AppLog.player(
                "playToEnd: suggestion=\(nextVideo.id) active=\(active)"
            )
            if active {
                self.showAutoplayOverlay(for: nextVideo)
            } else {
                self.navigateTo(nextVideo)
            }
        }
    }

    @objc
    func playerItemNewErrorLogEntry(
        _ note: Notification
    ) {
        guard let item =
            note.object as? AVPlayerItem,
            let events = item.errorLog()?.events,
            let last = events.last
        else {
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
        if last.errorStatusCode == 403 {
            hasSeenPlaybackError = true
            if !isRecoveringPlayback {
                AppLog.player(
                    "403 detected — scheduling recovery"
                )
                recoverPlayback()
            }
        }
    }

    func showPlaybackError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.playerSpinner.stopAnimating()
            self?.playerStatusLabel.text =
                "播放错误: \(message)"
            self?.playerStatusLabel.textColor =
                .systemRed
        }
    }
}
