import AVFoundation
import UIKit

// MARK: - Background / Foreground

extension PlaybackFacade {
    func prepareBackgroundAudioItem() {
        backgroundAudioObservation = nil
        guard let item = makeBackgroundAudioItem() else {
            backgroundAudioItem = nil
            return
        }
        backgroundAudioItem = item
        observeBackgroundAudioItem(item)
    }
}

extension PlaybackFacade {
    func makeBackgroundAudioItem() -> AVPlayerItem? {
        makePlaylistItem(
            path: "audio-master.m3u8",
            forwardBufferDuration:
                PlaybackBufferPolicy.backgroundBufferDuration
        )
    }

    func observeBackgroundAudioItem(_ item: AVPlayerItem) {
        backgroundAudioObservation = item.observe(
            \.status,
            options: [.new]
        ) { [weak self] observed, _ in
            self?.handleBackgroundAudioStatus(observed)
        }
    }

    func handleBackgroundAudioStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            backgroundAudioObservation = nil
            AppLog.player("background audio prewarmed")
        case .failed:
            backgroundAudioObservation = nil
            backgroundAudioItem = nil
            let message = item.error?.localizedDescription
                ?? "unknown"
            AppLog.player(
                "background audio prewarm failed: \(message)"
            )
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func audioPlaylistItem() -> AVPlayerItem? {
        if let item = backgroundAudioItem {
            backgroundAudioItem = nil
            backgroundAudioObservation = nil
            return item
        }
        return makeBackgroundAudioItem()
    }

    func shouldRestoreInlinePlayback(
        player: AVPlayer
    ) -> Bool {
        if backgroundPlaybackMode == .audioOnlyHLS {
            return true
        }
        guard let item = player.currentItem else {
            return false
        }
        let hasVideoTrack = item.tracks.contains {
            $0.assetTrack?.mediaType == .video
        }
        return !hasVideoTrack
    }

    func makePlaylistItem(
        path: String,
        forwardBufferDuration: TimeInterval
    ) -> AVPlayerItem? {
        guard let loader = hlsPlaylistLoader,
              let playlistURL = URL(
                  string: "\(HLSGenerator.scheme)://\(path)"
              ) else {
            return nil
        }
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey": activePlaybackHeaders
        ]
        let asset = AVURLAsset(url: playlistURL, options: options)
        asset.resourceLoader.setDelegate(
            loader,
            queue: loader.loaderQueue
        )
        let item = AVPlayerItem(asset: asset)
        PlaybackBufferPolicy.configure(
            item: item,
            forwardBufferDuration: forwardBufferDuration
        )
        return item
    }
}
