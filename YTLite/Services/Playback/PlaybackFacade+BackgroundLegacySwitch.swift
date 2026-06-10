import AVFoundation

extension PlaybackFacade {
    /// Background playback is handled entirely by AVAudioSession
    /// (.playback category) and NowPlayingService — no playlist
    /// switch needed. Explicitly resume play() to guard against
    /// the player being paused during the active→background transition.
    func handleAppDidEnterBackground(player: AVPlayer) {
        backgroundRestoreTime = player.currentTime()
        backgroundEnteredAt = Date()
        let wasPlaying = player.rate > 0
        let secs = CMTimeGetSeconds(backgroundRestoreTime)
        AppLog.player(
            "background: at \(secs)s wasPlaying=\(wasPlaying)"
        )
        if wasPlaying {
            player.play()
        }
    }

    /// Resume playback if it was active before backgrounding.
    func handleAppWillEnterForeground(player: AVPlayer) {
        let wasPlaying = backgroundEnteredAt != nil
        backgroundEnteredAt = nil
        AppLog.player("foreground: resuming wasPlaying=\(wasPlaying)")
        if wasPlaying {
            player.play()
        }
    }
}

private extension PlaybackFacade {
    func makeForegroundRestoreContext() -> (
        time: CMTime,
        seconds: Double
    ) {
        let elapsed = backgroundEnteredAt.map {
            Date().timeIntervalSince($0)
        } ?? 0
        let seconds =
            CMTimeGetSeconds(backgroundRestoreTime) + elapsed
        let time = CMTime(
            seconds: seconds,
            preferredTimescale: 1_000
        )
        return (time, seconds)
    }

    func seekForBackgroundSwitch(player: AVPlayer) {
        player.seek(
            to: backgroundRestoreTime,
            toleranceBefore: CMTime(
                seconds: 1,
                preferredTimescale: 1_000
            ),
            toleranceAfter: CMTime(
                seconds: 1,
                preferredTimescale: 1_000
            )
        ) { [weak player] _ in
            // Play only after seek is positioned — avoids
            // starting from 0 before seek completes.
            player?.play()
        }
    }

    func seekForForegroundSwitch(
        player: AVPlayer,
        restoreTime: CMTime
    ) {
        player.seek(
            to: restoreTime,
            toleranceBefore: CMTime(
                seconds: 0.5,
                preferredTimescale: 1_000
            ),
            toleranceAfter: CMTime(
                seconds: 0.5,
                preferredTimescale: 1_000
            )
        ) { [weak self, weak player] _ in
            player?.play()
            self?.prepareBackgroundAudioItem()
        }
    }

    func logBackgroundSwitchReady(seconds: Double) {
        AppLog.player(
            "background switch ready:"
                + " path=audio-master.m3u8"
                + " restore=\(seconds)s"
        )
    }

    func logForegroundSwitchReady(seconds: Double) {
        AppLog.player(
            "foreground switch ready:"
                + " path=master.m3u8"
                + " restore=\(seconds)s"
        )
    }

    func replaceCurrentItemDirectly(
        on player: AVPlayer,
        with item: AVPlayerItem
    ) {
        if let oldItem = player.currentItem {
            context?.stopObservingPlayerItem(oldItem)
        }
        context?.startObservingPlayerItem(item)
        player.replaceCurrentItem(with: item)
    }
}
