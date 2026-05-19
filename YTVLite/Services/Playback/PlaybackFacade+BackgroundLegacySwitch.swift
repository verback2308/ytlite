import AVFoundation

extension PlaybackFacade {
    func handleAppDidEnterBackground(player: AVPlayer) {
        backgroundRestoreTime = player.currentTime()
        backgroundEnteredAt = Date()
        let wasPlaying = player.rate > 0
        let secs = CMTimeGetSeconds(backgroundRestoreTime)
        AppLog.player(
            "background playback continuing at \(secs)s"
        )
        guard wasPlaying,
              let item = audioPlaylistItem() else {
            backgroundPlaybackMode = .inline
            return
        }
        beginPlaylistSwitchBackgroundTask()
        replaceCurrentItemDirectly(on: player, with: item)
        backgroundPlaybackMode = .audioOnlyHLS
        seekForBackgroundSwitch(player: player)
        player.play()
        logBackgroundSwitchReady(seconds: secs)
    }

    func handleAppWillEnterForeground(player: AVPlayer) {
        endPlaylistSwitchBackgroundTask()
        guard shouldRestoreInlinePlayback(player: player),
              let item = makePlaylistItem(
                  path: "master.m3u8",
                  forwardBufferDuration:
                    PlaybackBufferPolicy
                    .defaultForwardBufferDuration
              ) else {
            backgroundEnteredAt = nil
            return
        }
        let restoreContext = makeForegroundRestoreContext()
        backgroundEnteredAt = nil
        backgroundRestoreTime = restoreContext.time
        AppLog.player(
            "foreground playback continuing at \(restoreContext.seconds)s"
        )
        replaceCurrentItemDirectly(on: player, with: item)
        backgroundPlaybackMode = .inline
        seekForForegroundSwitch(
            player: player,
            restoreTime: restoreContext.time
        )
        logForegroundSwitchReady(seconds: restoreContext.seconds)
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
        )
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
