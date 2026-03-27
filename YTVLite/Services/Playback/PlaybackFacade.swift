import AVFoundation

// MARK: - PlaybackFacade

/// Owns the playback pipeline: PoToken minting → fetchDirectPlayback → onesie fallback
/// → strategy selection. WatchViewController delegates all "how to start" logic here
/// and remains responsible only for attaching the resulting AVPlayer to its UI.
final class PlaybackFacade {

    // MARK: Context

    /// The PlaybackContext (WatchViewController) used to attach player items and show errors.
    weak var context: PlaybackContext?

    // MARK: State — readable by WatchViewController

    /// Set after a successful DASH/HLS stream selection; used by the quality picker.
    private(set) var activePlaybackInfo: DirectPlaybackInfo?

    /// The client used for the current stream; needed when switching quality.
    private(set) var activePlaybackClient: DirectPlaybackClient = .androidVR

    /// HTTP headers for the current stream; set by WatchVC after buildHLSAndPlay.
    var activePlaybackHeaders: [String: String] = [:]

    /// Current video format itag; set by WatchVC after buildHLSAndPlay.
    var activeVideoFormat: DashFormatInfo?

    /// HLS playlist loader for generated HLS; set by WatchVC after attaching the player.
    var hlsPlaylistLoader: HLSPlaylistLoader?

    // MARK: Background/foreground state

    var backgroundRestoreTime: CMTime = .zero
    var backgroundEnteredAt: Date?

    // MARK: Private state

    private var activeDirectPlaybackClient: DirectPlaybackClient = .androidVR

    // MARK: - Public API

    /// Starts the full playback pipeline for a given video.
    func start(videoId: String,
               apiClient: WatchService,
               cancellationToken: CancellationToken,
               client: DirectPlaybackClient = .androidVR) {
        activeDirectPlaybackClient = client
        context?.updateStatusLabel("Minting PoToken...")

        WebPoTokenService.shared.fetchSessionToken(identifier: videoId) { [weak self] tokenResult in
            guard let self, !cancellationToken.isCancelled else { return }

            let poToken: String?
            switch tokenResult {
            case .success(let token): poToken = token
            case .failure(let error):
                AppLog.player("PoToken mint failed: \(error), proceeding without")
                poToken = nil
            }

            DispatchQueue.main.async {
                self.context?.updateStatusLabel("Resolving direct stream...")
            }

            apiClient.fetchDirectPlayback(videoId: videoId, client: client, poToken: poToken,
                                          cancellationToken: cancellationToken) { [weak self] result in
                switch result {
                case .failure(let error):
                    self?.context?.showPlaybackError(error.localizedDescription)
                case .success(let info):
                    self?.startDirectPlayback(info, videoId: videoId, client: client,
                                              cancellationToken: cancellationToken, apiClient: apiClient)
                }
            }
        }
    }

    /// Resets all playback state (call when loading a new video).
    func reset() {
        hlsPlaylistLoader = nil
        activePlaybackInfo = nil
        activeVideoFormat = nil
        activePlaybackHeaders = [:]
        backgroundRestoreTime = .zero
        backgroundEnteredAt = nil
        activeDirectPlaybackClient = .androidVR
    }

    // MARK: - Background / Foreground

    func handleAppDidEnterBackground(player: AVPlayer) {
        guard let loader = hlsPlaylistLoader else { return }

        backgroundRestoreTime = player.currentTime()
        backgroundEnteredAt = Date()

        let audioMasterURL = URL(string: "\(HLSGenerator.scheme)://audio-master.m3u8")!
        let assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": activePlaybackHeaders]
        let audioAsset = AVURLAsset(url: audioMasterURL, options: assetOptions)
        audioAsset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        let audioItem = AVPlayerItem(asset: audioAsset)
        audioItem.preferredForwardBufferDuration = 10.0
        player.replaceCurrentItem(with: audioItem)
        player.seek(to: backgroundRestoreTime,
                    toleranceBefore: CMTime(seconds: 1, preferredTimescale: 1000),
                    toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1000))
        player.play()
        AppLog.player("switched to audio-only HLS at \(CMTimeGetSeconds(backgroundRestoreTime))s")
    }

    func handleAppWillEnterForeground(player: AVPlayer) {
        guard let loader = hlsPlaylistLoader else {
            backgroundEnteredAt = nil
            return
        }

        let elapsed = backgroundEnteredAt.map { Date().timeIntervalSince($0) } ?? 0
        let restoreSeconds = CMTimeGetSeconds(backgroundRestoreTime) + elapsed
        let restoreTime = CMTime(seconds: restoreSeconds, preferredTimescale: 1000)
        backgroundEnteredAt = nil

        let masterURL = URL(string: "\(HLSGenerator.scheme)://master.m3u8")!
        let assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": activePlaybackHeaders]
        let asset = AVURLAsset(url: masterURL, options: assetOptions)
        asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 5.0
        player.replaceCurrentItem(with: item)
        player.seek(to: restoreTime,
                    toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 1000),
                    toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 1000)) { [weak player] _ in
            player?.play()
        }
        AppLog.player("restored video+audio HLS at \(restoreSeconds)s (base=\(CMTimeGetSeconds(backgroundRestoreTime))s + elapsed=\(String(format: "%.1f", elapsed))s)")
    }

    // MARK: - Private pipeline

    private func startDirectPlayback(_ info: DirectPlaybackInfo,
                                     videoId: String,
                                     client: DirectPlaybackClient,
                                     cancellationToken: CancellationToken,
                                     apiClient: WatchService) {
        AppLog.player("startDirectPlayback (\(client)): progressive=\(info.progressiveURL?.absoluteString.prefix(80) ?? "nil") hls=\(info.hlsManifestURL != nil) dash=\(info.dashManifestURL != nil) video=\(info.videoURL != nil) audio=\(info.audioURL != nil) sabr=\(info.serverAbrStreamingURL != nil) quality=\(info.qualityLabel ?? "nil") visitorData=\(info.visitorData?.prefix(20) ?? "nil")")

        if info.progressiveURL != nil || info.hlsManifestURL != nil ||
            info.dashManifestURL != nil || (info.videoURL != nil && info.audioURL != nil) {
            AppLog.player("trying direct playback (skip onesie) for \(client)")
            playDirectStream(info, client: client)
            return
        }

        if let sabrURL = info.serverAbrStreamingURL {
            let videoUstreamerLength = info.videoPlaybackUstreamerConfig?.count ?? 0
            let onesieUstreamerLength = info.onesieUstreamerConfig?.count ?? 0
            AppLog.player("SABR candidate available (\(client)): \(sabrURL.absoluteString.prefix(80)), ustreamer=\(info.hasVideoPlaybackUstreamerConfig), videoUstreamerLen=\(videoUstreamerLength), onesieUstreamerLen=\(onesieUstreamerLength)")
        }

        guard let visitorData = info.visitorData, !visitorData.isEmpty else {
            context?.showPlaybackError("Missing visitor data for onesie playback.")
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.context?.updateStatusLabel("Minting WebPO tokens...")
        }

        let group = DispatchGroup()
        var contentToken: String?

        group.enter()
        WebPoTokenService.shared.fetchSessionToken(identifier: videoId) { result in
            if case .success(let token) = result { contentToken = token }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let contentPlaybackNonce = Self.makeContentPlaybackNonce()

            guard let contentPoToken = contentToken, !contentPoToken.isEmpty else {
                self.context?.showPlaybackError("Failed to mint content WebPO token")
                return
            }

            self.context?.updateStatusLabel("Fetching stream via onesie...")
            OnesieService.shared.fetchPlaybackBootstrap(
                videoId: videoId,
                visitorData: visitorData,
                poToken: contentPoToken,
                contentPlaybackNonce: contentPlaybackNonce
            ) { [weak self] onesieResult in
                guard let self else { return }
                switch onesieResult {
                case .success(let bootstrap):
                    self.handleOnesieBootstrap(bootstrap, originalInfo: info, client: client,
                                               contentPoToken: contentPoToken,
                                               contentPlaybackNonce: contentPlaybackNonce)
                case .failure(let error):
                    AppLog.player("onesie failed (\(error))")
                    self.context?.showPlaybackError("Onesie bootstrap failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleOnesieBootstrap(_ bootstrap: OnesiePlaybackBootstrap,
                                       originalInfo: DirectPlaybackInfo,
                                       client: DirectPlaybackClient,
                                       contentPoToken: String,
                                       contentPlaybackNonce: String) {
        let typeSummary = bootstrap.responseParts
            .map { "\($0.type)(c\($0.compressionType))" }
            .joined(separator: ",")
        AppLog.player("onesie bootstrap ready proxy=\(bootstrap.proxyStatus) http=\(bootstrap.httpStatus) parts=[\(typeSummary)]")

        guard let refreshedInfo = InnertubeClient.parsePlayerJSON(bootstrap.playerJSON) else {
            AppLog.player("onesie player JSON parse failed")
            context?.showPlaybackError("Onesie returned an unusable player response.")
            return
        }

        let effectiveInfo = DirectPlaybackInfo(
            hlsManifestURL:              refreshedInfo.hlsManifestURL,
            dashManifestURL:             refreshedInfo.dashManifestURL,
            progressiveURL:              refreshedInfo.progressiveURL,
            videoURL:                    refreshedInfo.videoURL,
            audioURL:                    refreshedInfo.audioURL,
            serverAbrStreamingURL:       refreshedInfo.serverAbrStreamingURL,
            videoPlaybackUstreamerConfig: refreshedInfo.videoPlaybackUstreamerConfig ?? originalInfo.videoPlaybackUstreamerConfig,
            onesieUstreamerConfig:       refreshedInfo.onesieUstreamerConfig ?? originalInfo.onesieUstreamerConfig,
            sabrVideoFormat:             refreshedInfo.sabrVideoFormat,
            sabrAudioFormat:             refreshedInfo.sabrAudioFormat,
            videoItag:                   refreshedInfo.videoItag,
            audioItag:                   refreshedInfo.audioItag,
            qualityLabel:                refreshedInfo.qualityLabel,
            visitorData:                 refreshedInfo.visitorData ?? originalInfo.visitorData,
            hasVideoPlaybackUstreamerConfig: refreshedInfo.hasVideoPlaybackUstreamerConfig || originalInfo.hasVideoPlaybackUstreamerConfig,
            dashVideoFormat:             refreshedInfo.dashVideoFormat,
            dashAudioFormat:             refreshedInfo.dashAudioFormat,
            allDashVideoFormats:         refreshedInfo.allDashVideoFormats,
            duration:                    refreshedInfo.duration
        )

        guard effectiveInfo.hlsManifestURL != nil || effectiveInfo.progressiveURL != nil ||
              (effectiveInfo.videoURL != nil && effectiveInfo.audioURL != nil) else {
            context?.showPlaybackError("Onesie returned no playable streams.")
            return
        }

        playDirectStream(effectiveInfo, client: client)
    }

    private func playDirectStream(_ info: DirectPlaybackInfo, client: DirectPlaybackClient) {
        AppLog.player("playDirectStream: hls=\(info.hlsManifestURL != nil) dash=\(info.dashManifestURL != nil) progressive=\(info.progressiveURL != nil) video+audio=\(info.videoURL != nil && info.audioURL != nil) sabr=\(info.serverAbrStreamingURL != nil)")

        guard let strategy = PlaybackStrategySelector.select(for: info) else {
            context?.showPlaybackError("No playable direct stream available.")
            return
        }

        if info.dashVideoFormat != nil {
            activePlaybackInfo = info
            activePlaybackClient = client
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let context = self.context else { return }
            strategy.play(info, client: client, context: context)
        }
    }

    private static func makeContentPlaybackNonce(length: Int = 16) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
