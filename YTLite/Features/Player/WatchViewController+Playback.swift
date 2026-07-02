import AVFoundation
import AVKit
import UIKit

// MARK: - Playback

extension WatchViewController {
    func startPlayback() {
        playbackFacade.watchtimeTracker.timeProvider = { [weak self] in
            self?.videoPlayerView?.player?.currentTime().seconds ?? 0
        }
        playbackFacade.start(
            videoId: initialVideo.id,
            apiClient: client,
            cancellationToken: pageLoadToken
        )
    }

    func prepareDirectPlaybackURL(
        baseURL: URL,
        client: DirectPlaybackClient,
        poToken: String?
    ) -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            return baseURL
        }
        var items = components.queryItems ?? []
        items.removeAll {
            $0.name == "pot" || $0.name == "cver"
        }
        if let pot = poToken, !pot.isEmpty {
            items.append(
                URLQueryItem(name: "pot", value: pot)
            )
        }
        items.append(URLQueryItem(
            name: "cver",
            value: client.clientVersion
        ))
        components.queryItems = items
        return components.url ?? baseURL
    }

    func attachComposedPlayer(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String],
        completion: @escaping (Bool) -> Void
    ) {
        AdaptiveCompositionBuilder.build(
            videoURL: videoURL,
            audioURL: audioURL,
            headers: headers
        ) { [weak self] item in
            guard let self, let item else {
                completion(false)
                return
            }
            attachPlayer(item: item)
            completion(true)
        }
    }

    func prepareAdaptiveUpgrade(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String],
        quality: String
    ) {
        AdaptiveCompositionBuilder.build(
            videoURL: videoURL,
            audioURL: audioURL,
            headers: headers
        ) { [weak self] item in
            guard let self, let item else {
                return
            }
            performAdaptiveSwitch(
                item: item,
                quality: quality
            )
        }
    }

    func performAdaptiveSwitch(
        item: AVPlayerItem,
        quality: String
    ) {
        let player = videoPlayerView?.player
        guard let player else {
            return
        }
        let currentTime = player.currentTime()
        let wasPlaying = player.rate > 0
        PlaybackBufferPolicy.configure(item: item)
        PlaybackBufferPolicy.configure(player: player)
        if let oldItem = player.currentItem {
            stopObservingPlayerItem(oldItem)
        }
        startObservingPlayerItem(item)
        player.replaceCurrentItem(with: item)
        player.seek(
            to: currentTime,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        if wasPlaying { player.play() }
        AppLog.player(
            "adaptive upgrade: switched to \(quality)"
        )
    }

    // swiftlint:disable:next function_parameter_count
    func buildHLSAndPlay(
        videoURL: URL,
        audioURL: URL,
        videoFormat: DashFormatInfo,
        audioFormat: DashFormatInfo,
        headers: [String: String],
        quality: String
    ) {
        playbackFacade.activeVideoFormat =
            videoFormat
        playbackFacade.activePlaybackHeaders =
            headers
        let input = HLSPlaybackBuilder.BuildInput(
            videoURL: videoURL,
            audioURL: audioURL,
            videoFormat: videoFormat,
            audioFormat: audioFormat,
            headers: headers
        )
        HLSPlaybackBuilder.build(
            input: input
        ) { [weak self] result in
            self?.handleHLSBuildResult(
                result,
                quality: quality
            )
        }
    }

    private func handleHLSBuildResult(
        _ result: HLSPlaybackBuilder.Result?,
        quality: String
    ) {
        guard let result else {
            fallbackToProgressivePlayback()
            return
        }
        DispatchQueue.main.async {
            self.playbackFacade
                .hlsPlaylistLoader =
                result.loader
            self.playbackFacade
                .prepareBackgroundAudioItem()
            self.attachPlayer(
                item: result.playerItem
            )
            AppLog.player(
                "HLS: player attached"
                    + " for \(quality)"
            )
        }
    }

    func fallbackToProgressivePlayback() {
        AppLog.player(
            "HLS: falling back to progressive + adaptive upgrade"
        )
        DispatchQueue.main.async {
            self.showPlaybackError(
                "HLS generation failed — no fallback available"
            )
        }
    }

    func attachPlayer(url: URL) {
        attachPlayer(item: AVPlayerItem(url: url))
    }

    func attachDirectPlayer(
        url: URL,
        visitorData: String?,
        client: DirectPlaybackClient
    ) {
        resetPlaybackSurfaces()
        let headers = makeDirectRequestHeaders(
            visitorData: visitorData,
            client: client
        )
        let prefix = url.absoluteString.prefix(120)
        AppLog.player(
            "attachDirectPlayer (\(client)):"
                + " url=\(prefix)..."
        )
        AppLog.player(
            "attachDirectPlayer headers: \(headers)"
        )
        let opts = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: opts)
        attachPlayer(item: AVPlayerItem(asset: asset))
    }

    func makeDirectRequestHeaders(
        visitorData: String?,
        client: DirectPlaybackClient
    ) -> [String: String] {
        client.streamHeaders(visitorData: visitorData)
    }

    func attachPlayer(
        item: AVPlayerItem,
        minimizeStalling: Bool = true
    ) {
        guard !pageLoadToken.isCancelled else {
            return
        }
        resetPlaybackSurfaces()
        playerSpinner.stopAnimating()
        playerStatusLabel.isHidden = true
        PlaybackBufferPolicy.configure(item: item)
        startObservingPlayerItem(item)
        let player = AVPlayer(playerItem: item)
        PlaybackBufferPolicy.configure(
            player: player,
            waitsToMinimizeStalling: minimizeStalling
        )
        let pv = getOrCreatePlayerView()
        configureSponsorBlock(on: pv)
        playerContainer.bringSubviewToFront(pv)
        pv.attach(player: player)
        player.play()
    }

    func getOrCreatePlayerView() -> VideoPlayerView {
        if let existing = videoPlayerView {
            return existing
        }
        let playerView = VideoPlayerView()
        playerView
            .translatesAutoresizingMaskIntoConstraints
            = false
        playerView.delegate = self
        playerContainer.addSubview(playerView)
        applyEdgeConstraints(playerView, to: playerContainer)
        videoPlayerView = playerView
        if !captionTracks.isEmpty {
            playerView.setCaptionTracks(
                captionTracks,
                activeLanguage: activeSubtitleLanguage
            )
            playerView.onCCTapped = { [weak self] in
                self?.showSubtitlePicker()
            }
        }
        return playerView
    }

    func configureSponsorBlock(
        on playerView: VideoPlayerView
    ) {
        sponsorBlock.attach(to: playerView)
        playerView.onTimeUpdate = { [weak self] time in
            self?.sponsorBlock.checkTime(time)
            NowPlayingService.shared.updatePosition(time)
            self?.videoPlayerView?.updateSubtitle(at: time)
        }
        playerView.onSkipTapped = { [weak self] in
            self?.sponsorBlock.skipCurrentSegment()
        }
        if !sponsorBlock.segments.isEmpty {
            playerView.setSponsorSegments(
                sponsorBlock.segments
            )
        }
    }

    func resetPlaybackSurfaces() {
        videoPlayerView?.player?.pause()
        if let existing =
            videoPlayerView?.player?.currentItem {
            stopObservingPlayerItem(existing)
        }
        videoPlayerView?.detach()
        NowPlayingService.shared.endSession()
    }
}
