import Foundation

/// Generates an HLS playlist from DASH SIDX segment info and plays it via AVPlayer.
/// Instant 720p without needing a server-side HLS manifest.
struct GeneratedHLSPlaybackStrategy: PlaybackStrategy {

    func canHandle(_ info: DirectPlaybackInfo) -> Bool {
        info.dashVideoFormat != nil && info.dashAudioFormat != nil
    }

    func play(_ info: DirectPlaybackInfo, client: DirectPlaybackClient, context: PlaybackContext) {
        guard let dashVideo = info.dashVideoFormat, let dashAudio = info.dashAudioFormat else { return }

        let videoURL = context.prepareDirectPlaybackURL(baseURL: dashVideo.url, client: client, poToken: nil)
        let audioURL = context.prepareDirectPlaybackURL(baseURL: dashAudio.url, client: client, poToken: nil)
        let quality = info.qualityLabel ?? "720p"
        let headers = context.makeDirectRequestHeaders(visitorData: info.visitorData, client: client)

        AppLog.player("strategy: generated HLS (\(quality)) v=itag\(dashVideo.itag) a=itag\(dashAudio.itag) client=\(client)")
        context.updateStatusLabel("Loading \(quality) stream...")
        context.buildHLSAndPlay(videoURL: videoURL, audioURL: audioURL,
                                videoFormat: dashVideo, audioFormat: dashAudio,
                                headers: headers, quality: quality)
    }
}
