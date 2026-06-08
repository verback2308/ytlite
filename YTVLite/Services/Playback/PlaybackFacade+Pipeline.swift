// swiftlint:disable file_length
import AVFoundation

extension PlaybackFacade {
    func fetchPoTokenAndPlay(
        _ ctx: PlaybackPipelineContext
    ) {
        let cancel = ctx.cancellationToken
        WebPoTokenService.shared.fetchSessionToken(
            identifier: ctx.videoId
        ) { [weak self] tokenResult in
            guard let self, !cancel.isCancelled else {
                return
            }
            let poToken: String?
            switch tokenResult {
            case .success(let token):
                poToken = token
            case .failure(let error):
                AppLog.player(
                    "PoToken failed: \(error)"
                )
                poToken = nil
            }
            DispatchQueue.main.async {
                self.context?.updateStatusLabel(
                    "Resolving direct stream..."
                )
            }
            self.fetchDirectPlayback(
                poToken: poToken,
                pipelineContext: ctx
            )
        }
    }

    private func fetchDirectPlayback(
        poToken: String?,
        pipelineContext ctx: PlaybackPipelineContext
    ) {
        ctx.apiClient.fetchDirectPlayback(
            videoId: ctx.videoId,
            client: ctx.client,
            poToken: poToken,
            cancellationToken: ctx.cancellationToken
        ) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.context?.showPlaybackError(
                    error.localizedDescription
                )
            case .success(let info):
                self?.startDirectPlayback(
                    info,
                    pipelineContext: ctx
                )
            }
        }
    }

    private func startDirectPlayback(
        _ info: DirectPlaybackInfo,
        pipelineContext ctx: PlaybackPipelineContext
    ) {
        logStartPlayback(info, client: ctx.client)
        if hasDirectStreams(info) {
            playDirectStream(
                info,
                client: ctx.client
            )
            return
        }
        logSabrInfo(info, client: ctx.client)
        guard let visitorData = info.visitorData,
              !visitorData.isEmpty else {
            context?.showPlaybackError(
                "Missing visitor data for onesie."
            )
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.context?.updateStatusLabel(
                "Minting WebPO tokens..."
            )
        }
        fetchOnesieBootstrap(
            info: info,
            visitorData: visitorData,
            pipelineContext: ctx
        )
    }

    private func fetchOnesieBootstrap(
        info: DirectPlaybackInfo,
        visitorData: String,
        pipelineContext ctx: PlaybackPipelineContext
    ) {
        let group = DispatchGroup()
        var contentToken: String?
        group.enter()
        WebPoTokenService.shared.fetchSessionToken(
            identifier: ctx.videoId
        ) { result in
            if case .success(let token) = result {
                contentToken = token
            }
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else {
                return
            }
            self.handleOnesieTokens(
                contentToken: contentToken,
                info: info,
                visitorData: visitorData,
                pipelineContext: ctx
            )
        }
    }

    private func handleOnesieTokens(
        contentToken: String?,
        info: DirectPlaybackInfo,
        visitorData: String,
        pipelineContext ctx: PlaybackPipelineContext
    ) {
        let nonce = Self.makeContentPlaybackNonce()
        guard let poToken = contentToken,
              !poToken.isEmpty else {
            context?.showPlaybackError(
                "Failed to mint content WebPO token"
            )
            return
        }
        context?.updateStatusLabel(
            "Fetching stream via onesie..."
        )
        let onesieCtx = OnesieContext(
            originalInfo: info,
            client: ctx.client,
            contentPoToken: poToken,
            contentPlaybackNonce: nonce
        )
        requestOnesieBootstrap(
            videoId: ctx.videoId,
            visitorData: visitorData,
            onesieContext: onesieCtx
        )
    }

    private func requestOnesieBootstrap(
        videoId: String,
        visitorData: String,
        onesieContext ctx: OnesieContext
    ) {
        OnesieService.shared.fetchPlaybackBootstrap(
            videoId: videoId,
            visitorData: visitorData,
            poToken: ctx.contentPoToken,
            cpn: ctx.contentPlaybackNonce
        ) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success(let bootstrap):
                self.handleOnesieBootstrap(
                    bootstrap,
                    onesieContext: ctx
                )
            case .failure(let error):
                AppLog.player(
                    "onesie failed (\(error))"
                )
                self.context?.showPlaybackError(
                    "Onesie failed: "
                        + error.localizedDescription
                )
            }
        }
    }

    private func handleOnesieBootstrap(
        _ bootstrap: OnesiePlaybackBootstrap,
        onesieContext: OnesieContext
    ) {
        logOnesieBootstrap(bootstrap)
        guard let refreshed = InnertubeClient
            .parsePlayerJSON(
                bootstrap.playerJSON
            ) else {
            AppLog.player("onesie JSON parse failed")
            context?.showPlaybackError(
                "Onesie returned unusable response."
            )
            return
        }
        let effective = mergePlaybackInfo(
            refreshed: refreshed,
            original: onesieContext.originalInfo
        )
        guard hasPlayableStreams(effective) else {
            context?.showPlaybackError(
                "Onesie: no playable streams."
            )
            return
        }
        playDirectStream(
            effective,
            client: onesieContext.client
        )
    }

    private func mergePlaybackInfo(
        refreshed: DirectPlaybackInfo,
        original: DirectPlaybackInfo
    ) -> DirectPlaybackInfo {
        let vpuc = refreshed
            .videoPlaybackUstreamerConfig
            ?? original.videoPlaybackUstreamerConfig
        let ouc = refreshed.onesieUstreamerConfig
            ?? original.onesieUstreamerConfig
        let hasVpuc = refreshed
            .hasPlaybackUstreamerConfig
            || original.hasPlaybackUstreamerConfig
        return buildMergedInfo(
            refreshed: refreshed,
            vpuc: vpuc,
            ouc: ouc,
            hasVpuc: hasVpuc,
            original: original
        )
    }

    // swiftlint:disable function_parameter_count
    private func buildMergedInfo(
        refreshed: DirectPlaybackInfo,
        vpuc: String?,
        ouc: String?,
        hasVpuc: Bool,
        original: DirectPlaybackInfo
    ) -> DirectPlaybackInfo {
        DirectPlaybackInfo(
            hlsManifestURL: refreshed.hlsManifestURL,
            dashManifestURL: refreshed.dashManifestURL,
            progressiveURL: refreshed.progressiveURL,
            videoURL: refreshed.videoURL,
            audioURL: refreshed.audioURL,
            serverAbrStreamingURL: refreshed.serverAbrStreamingURL,
            videoPlaybackUstreamerConfig: vpuc,
            onesieUstreamerConfig: ouc,
            sabrVideoFormat: refreshed.sabrVideoFormat,
            sabrAudioFormat: refreshed.sabrAudioFormat,
            videoItag: refreshed.videoItag,
            audioItag: refreshed.audioItag,
            qualityLabel: refreshed.qualityLabel,
            visitorData: refreshed.visitorData
                ?? original.visitorData,
            hasPlaybackUstreamerConfig: hasVpuc,
            dashVideoFormat: refreshed.dashVideoFormat,
            dashAudioFormat: refreshed.dashAudioFormat,
            allDashVideoFormats: refreshed.allDashVideoFormats,
            duration: refreshed.duration,
            playbackTrackingURLs: refreshed.playbackTrackingURLs
                ?? original.playbackTrackingURLs
        )
    }
    // swiftlint:enable function_parameter_count

    private func playDirectStream(
        _ info: DirectPlaybackInfo,
        client: DirectPlaybackClient
    ) {
        logPlayDirect(info)
        guard let strategy = PlaybackStrategySelector
            .select(for: info) else {
            context?.showPlaybackError(
                "No playable direct stream."
            )
            return
        }
        activePlaybackInfo = info
        activePlaybackClient = client
        fetchWatchtimeAndTrack()
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let ctx = self.context else {
                return
            }
            strategy.play(
                info,
                client: client,
                context: ctx
            )
        }
    }

    private func hasDirectStreams(
        _ info: DirectPlaybackInfo
    ) -> Bool {
        let hasAdaptive = info.hlsManifestURL != nil
            || info.dashManifestURL != nil
            || (info.videoURL != nil && info.audioURL != nil)
        if hasAdaptive {
            return true
        }
        // Prefer SABR adaptive streaming over 360p progressive fallback
        if info.serverAbrStreamingURL != nil {
            return false
        }
        return info.progressiveURL != nil
    }

    private func hasPlayableStreams(
        _ info: DirectPlaybackInfo
    ) -> Bool {
        info.hlsManifestURL != nil
            || info.progressiveURL != nil
            || (info.videoURL != nil && info.audioURL != nil)
    }

    private func fetchWatchtimeAndTrack() {
        guard let videoId = currentVideoId,
              let apiClient = currentApiClient
        else {
            return
        }
        apiClient.fetchWatchtimeURLs(
            videoId: videoId
        ) { [weak self] urls in
            guard let urls,
                  let self
            else {
                return
            }
            self.watchtimeTracker.start(
                videoId: videoId,
                urls: urls
            )
        }
    }
}
