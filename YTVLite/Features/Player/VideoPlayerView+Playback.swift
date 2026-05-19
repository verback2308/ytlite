import AVFoundation
import AVKit
import UIKit

// MARK: - Playback API

extension VideoPlayerView {
    func attach(player newPlayer: AVPlayer) {
        player = newPlayer
        playerLayer.isHidden = false
        playerLayer.player = newPlayer
        addPeriodicObserver()
        addPlayerObservers()
        updatePlayPauseIcon()
        setupPiP()
    }

    func detach() {
        removePeriodicObserver()
        removePlayerObservers()
        playerLayer.isHidden = false
        playerLayer.player = nil
        player = nil
        hideSkipButton()
        sponsorSegments = []
        seekBar.setSegments([])
    }

    func setSponsorSegments(
        _ segments: [SponsorBlockSegment]
    ) {
        sponsorSegments = segments
        refreshSponsorSeekBar()
    }

    func showSkipButton(categoryName: String) {
        skipButton.setTitle(
            "Skip \(categoryName)",
            for: .normal
        )
        skipButton.isHidden = false
    }

    func hideSkipButton() {
        skipButton.isHidden = true
    }

    func refreshSponsorSeekBar() {
        guard duration > 0 else {
            return
        }
        let normalized = sponsorSegments
            .filter {
                SponsorBlockService.skipBehavior(
                    for: $0.category
                ) != .disabled
            }
            .map {
                SeekBarSegment(
                    start: $0.startTime / duration,
                    end: $0.endTime / duration,
                    color: $0.category.seekBarColor
                )
            }
        seekBar.setSegments(normalized)
    }

    // MARK: - Periodic Observer

    func addPeriodicObserver() {
        guard let player else {
            return
        }
        let interval = CMTime(
            seconds: 0.5,
            preferredTimescale: 600
        )
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.updateProgress(time: time)
        }
    }

    func removePeriodicObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    // MARK: - Player Observers

    func addPlayerObservers() {
        guard let player else {
            return
        }
        observeRate(on: player)
        observeTimeControl(on: player)
        observeDuration(on: player)
    }

    private func observeRate(on player: AVPlayer) {
        rateObservation = player.observe(
            \.rate,
            options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updatePlayPauseIcon()
            }
        }
    }

    private func observeTimeControl(on player: AVPlayer) {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.new]
        ) { [weak self] observed, _ in
            DispatchQueue.main.async {
                switch observed.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self?.spinner.startAnimating()
                    self?.setCenter(hidden: true)
                case .playing, .paused:
                    self?.spinner.stopAnimating()
                    self?.setCenter(hidden: false)
                @unknown default:
                    break
                }
            }
        }
    }

    private func observeDuration(on player: AVPlayer) {
        statusObservation = player.currentItem?.observe(
            \.duration,
            options: [.new]
        ) { [weak self] item, _ in
            DispatchQueue.main.async {
                let secs = CMTimeGetSeconds(item.duration)
                if secs.isFinite, secs > 0 {
                    self?.duration = secs
                    self?.durationLabel.text = formatTime(
                        secs
                    )
                    self?.refreshSponsorSeekBar()
                }
            }
        }
    }

    func removePlayerObservers() {
        rateObservation = nil
        statusObservation = nil
        timeControlObservation = nil
    }

    // MARK: - Progress

    func updateProgress(time: CMTime) {
        guard duration > 0 else {
            return
        }
        let secs = CMTimeGetSeconds(time)
        currentTimeLabel.text = formatTime(secs)
        if !seekBar.isScrubbing {
            seekBar.setProgress(secs / duration)
        }
        updateBuffer(at: time)
        onTimeUpdate?(secs)
    }

    private func updateBuffer(at time: CMTime) {
        guard let item = player?.currentItem else {
            return
        }
        let buffered = item.loadedTimeRanges
            .compactMap { $0 as? CMTimeRange }
            .filter {
                CMTimeRangeContainsTime($0, time: time)
            }
            .map {
                CMTimeGetSeconds($0.start)
                    + CMTimeGetSeconds($0.duration)
            }
            .max() ?? 0
        seekBar.setBuffer(buffered / duration)
    }
}
