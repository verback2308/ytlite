import Foundation

/// Plays adaptive (video + audio) directly when no progressive stream is available.
/// Slower to start than progressive but gives better quality.
struct AdaptiveOnlyPlaybackStrategy: PlaybackStrategy {
    func canHandle(_ info: DirectPlaybackInfo) -> Bool {
        info.videoURL != nil && info.audioURL != nil
    }

    func play(_ info: DirectPlaybackInfo, client: DirectPlaybackClient, context: PlaybackContext) {
        guard let videoURL = info.videoURL,
              let audioURL = info.audioURL
        else {
            return
        }

        let preparedVideoURL = context.prepareDirectPlaybackURL(
            baseURL: videoURL,
            client: client,
            poToken: nil
        )
        let preparedAudioURL = context.prepareDirectPlaybackURL(
            baseURL: audioURL,
            client: client,
            poToken: nil
        )
        let headers = context.makeDirectRequestHeaders(
            visitorData: info.visitorData,
            client: client
        )
        let quality = info.qualityLabel ?? "?"

        AppLog.player("strategy: adaptive only (no progressive), quality=\(quality)")
        context.updateStatusLabel("Loading \(quality) stream...")
        context.attachComposedPlayer(
            videoURL: preparedVideoURL,
            audioURL: preparedAudioURL,
            headers: headers
        ) { _ in }
    }
}
