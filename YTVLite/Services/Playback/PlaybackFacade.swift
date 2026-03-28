import AVFoundation

struct PlaybackPipelineContext {
    let videoId: String
    let client: DirectPlaybackClient
    let cancellationToken: CancellationToken
    let apiClient: WatchService
}

struct OnesieContext {
    let originalInfo: DirectPlaybackInfo
    let client: DirectPlaybackClient
    let contentPoToken: String
    let contentPlaybackNonce: String
}

/// Owns the playback pipeline: PoToken minting →
/// fetchDirectPlayback → onesie fallback → strategy
/// selection.
final class PlaybackFacade {
    weak var context: PlaybackContext?
    var activePlaybackInfo: DirectPlaybackInfo?
    var activePlaybackClient: DirectPlaybackClient = .androidVR
    var activePlaybackHeaders: [String: String] = [:]
    var activeVideoFormat: DashFormatInfo?
    var hlsPlaylistLoader: HLSPlaylistLoader?
    var backgroundRestoreTime: CMTime = .zero
    var backgroundEnteredAt: Date?
    private var activeDirectPlaybackClient: DirectPlaybackClient = .androidVR

    static func makeContentPlaybackNonce(
        length: Int = 16
    ) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        return String(
            (0..<length).compactMap { _ in
                Array(chars).randomElement()
            }
        )
    }
}

// MARK: - Public API

extension PlaybackFacade {
    func start(
        videoId: String,
        apiClient: WatchService,
        cancellationToken: CancellationToken,
        client: DirectPlaybackClient = .androidVR
    ) {
        activeDirectPlaybackClient = client
        context?.updateStatusLabel("Minting PoToken...")
        fetchPoTokenAndPlay(
            PlaybackPipelineContext(
                videoId: videoId,
                client: client,
                cancellationToken: cancellationToken,
                apiClient: apiClient
            )
        )
    }

    func reset() {
        hlsPlaylistLoader = nil
        activePlaybackInfo = nil
        activeVideoFormat = nil
        activePlaybackHeaders = [:]
        backgroundRestoreTime = .zero
        backgroundEnteredAt = nil
        activeDirectPlaybackClient = .androidVR
    }
}

// MARK: - Background / Foreground

extension PlaybackFacade {
    func handleAppDidEnterBackground(player: AVPlayer) {
        guard hlsPlaylistLoader != nil else {
            return
        }
        backgroundRestoreTime = player.currentTime()
        backgroundEnteredAt = Date()
        let scheme = HLSGenerator.scheme
        guard switchToHLSPlaylist(
            player: player,
            urlString: "\(scheme)://audio-master.m3u8",
            bufferDuration: 10.0
        ) else {
            return
        }
        let tol = CMTime(
            seconds: 1,
            preferredTimescale: 1_000
        )
        player.seek(
            to: backgroundRestoreTime,
            toleranceBefore: tol,
            toleranceAfter: tol
        )
        player.play()
        let secs = CMTimeGetSeconds(backgroundRestoreTime)
        AppLog.player("audio-only HLS at \(secs)s")
    }

    func handleAppWillEnterForeground(player: AVPlayer) {
        guard hlsPlaylistLoader != nil else {
            backgroundEnteredAt = nil
            return
        }
        let elapsed = backgroundEnteredAt
            .map { Date().timeIntervalSince($0) } ?? 0
        let base = CMTimeGetSeconds(backgroundRestoreTime)
        let secs = base + elapsed
        let time = CMTime(
            seconds: secs,
            preferredTimescale: 1_000
        )
        backgroundEnteredAt = nil
        let scheme = HLSGenerator.scheme
        guard switchToHLSPlaylist(
            player: player,
            urlString: "\(scheme)://master.m3u8",
            bufferDuration: 5.0
        ) else {
            return
        }
        seekToForeground(player: player, time: time)
        let fmt = String(format: "%.1f", elapsed)
        AppLog.player(
            "restored HLS at \(secs)s"
                + " (base=\(base)s + elapsed=\(fmt)s)"
        )
    }

    private func switchToHLSPlaylist(
        player: AVPlayer,
        urlString: String,
        bufferDuration: Double
    ) -> Bool {
        guard let loader = hlsPlaylistLoader,
              let url = URL(string: urlString) else {
            return false
        }
        let options: [String: Any] = [
            "AVURLAssetHTTPHeaderFieldsKey":
                activePlaybackHeaders
        ]
        let asset = AVURLAsset(
            url: url,
            options: options
        )
        asset.resourceLoader.setDelegate(
            loader,
            queue: loader.loaderQueue
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = bufferDuration
        player.replaceCurrentItem(with: item)
        return true
    }

    private func seekToForeground(
        player: AVPlayer,
        time: CMTime
    ) {
        let tol = CMTime(
            seconds: 0.5,
            preferredTimescale: 1_000
        )
        player.seek(
            to: time,
            toleranceBefore: tol,
            toleranceAfter: tol
        ) { [weak player] _ in
            player?.play()
        }
    }
}
