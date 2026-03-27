import Foundation

/// Generates an HLS playlist from DASH SIDX segment info and plays it via AVPlayer.
/// Instant 720p without needing a server-side HLS manifest.
struct GeneratedHLSPlaybackStrategy: PlaybackStrategy {
    func canHandle(_ info: DirectPlaybackInfo) -> Bool {
        info.dashVideoFormat != nil && info.dashAudioFormat != nil
    }

    func play(
        _ info: DirectPlaybackInfo,
        client: DirectPlaybackClient,
        context: PlaybackContext
    ) {
        guard let dashVideo = info.dashVideoFormat,
              let dashAudio = info.dashAudioFormat
        else {
            return
        }

        let prepared = preparePlayback(
            info: info,
            dashVideo: dashVideo,
            dashAudio: dashAudio,
            client: client,
            context: context
        )
        context.updateStatusLabel(
            "Loading \(prepared.quality) stream..."
        )
        context.buildHLSAndPlay(
            videoURL: prepared.videoURL,
            audioURL: prepared.audioURL,
            videoFormat: dashVideo,
            audioFormat: dashAudio,
            headers: prepared.headers,
            quality: prepared.quality
        )
    }

    private func preparePlayback( // swiftlint:disable:this function_parameter_count
        info: DirectPlaybackInfo,
        dashVideo: DashFormatInfo,
        dashAudio: DashFormatInfo,
        client: DirectPlaybackClient,
        context: PlaybackContext
    ) -> HLSPreparedPlayback {
        let videoURL = context.prepareDirectPlaybackURL(
            baseURL: dashVideo.url,
            client: client,
            poToken: nil
        )
        let audioURL = context.prepareDirectPlaybackURL(
            baseURL: dashAudio.url,
            client: client,
            poToken: nil
        )
        let quality = info.qualityLabel ?? "720p"
        let headers = context.makeDirectRequestHeaders(
            visitorData: info.visitorData,
            client: client
        )

        let tag = "strategy: generated HLS (\(quality)) "
            + "v=itag\(dashVideo.itag) "
            + "a=itag\(dashAudio.itag) client=\(client)"
        AppLog.player(tag)

        return HLSPreparedPlayback(
            videoURL: videoURL,
            audioURL: audioURL,
            headers: headers,
            quality: quality
        )
    }
}

private struct HLSPreparedPlayback {
    let videoURL: URL
    let audioURL: URL
    let headers: [String: String]
    let quality: String
}
