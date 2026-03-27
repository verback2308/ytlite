import Foundation

/// Starts progressive (360p) immediately for instant feedback, then upgrades to
/// adaptive (720p) in the background once the composition is ready.
struct ProgressiveWithUpgradePlaybackStrategy: PlaybackStrategy {

    func canHandle(_ info: DirectPlaybackInfo) -> Bool {
        info.progressiveURL != nil
    }

    func play(_ info: DirectPlaybackInfo, client: DirectPlaybackClient, context: PlaybackContext) {
        guard let progressiveURL = info.progressiveURL else { return }

        let preparedURL = context.prepareDirectPlaybackURL(baseURL: progressiveURL, client: client, poToken: nil)
        AppLog.player("strategy: progressive (360p) immediate start")
        context.updateStatusLabel("Loading stream...")
        context.attachDirectPlayer(url: preparedURL, visitorData: info.visitorData, client: client)

        guard let videoURL = info.videoURL, let audioURL = info.audioURL else { return }
        let preparedVideoURL = context.prepareDirectPlaybackURL(baseURL: videoURL, client: client, poToken: nil)
        let preparedAudioURL = context.prepareDirectPlaybackURL(baseURL: audioURL, client: client, poToken: nil)
        let headers = context.makeDirectRequestHeaders(visitorData: info.visitorData, client: client)
        let quality = info.qualityLabel ?? "720p"
        AppLog.player("strategy: scheduling background adaptive upgrade to \(quality)")
        context.prepareAdaptiveUpgrade(videoURL: preparedVideoURL, audioURL: preparedAudioURL,
                                       headers: headers, quality: quality)
    }
}
