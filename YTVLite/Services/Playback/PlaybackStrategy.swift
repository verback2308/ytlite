import AVFoundation
import Foundation

// MARK: - PlaybackContext

/// All side-effects a PlaybackStrategy needs from its host view controller.
/// WatchViewController conforms to this protocol.
protocol PlaybackContext: AnyObject {
    func attachPlayer(url: URL)
    func attachDirectPlayer(
        url: URL,
        visitorData: String?,
        client: DirectPlaybackClient
    )
    func attachComposedPlayer(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String],
        completion: @escaping (Bool) -> Void
    )
    // swiftlint:disable:next function_parameter_count
    func buildHLSAndPlay(
        videoURL: URL,
        audioURL: URL,
        videoFormat: DashFormatInfo,
        audioFormat: DashFormatInfo,
        headers: [String: String],
        quality: String
    )
    func prepareAdaptiveUpgrade(
        videoURL: URL,
        audioURL: URL,
        headers: [String: String],
        quality: String
    )
    func updateStatusLabel(_ text: String)
    func showPlaybackError(_ message: String)
    func makeDirectRequestHeaders(
        visitorData: String?,
        client: DirectPlaybackClient
    ) -> [String: String]
    func prepareDirectPlaybackURL(
        baseURL: URL,
        client: DirectPlaybackClient,
        poToken: String?
    ) -> URL
    func startObservingPlayerItem(_ item: AVPlayerItem)
    func stopObservingPlayerItem(_ item: AVPlayerItem)
}

// MARK: - PlaybackStrategy

/// A single playback strategy. Strategies are tried in priority order by
/// PlaybackStrategySelector; the first one whose canHandle(_:) returns true is used.
protocol PlaybackStrategy {
    func canHandle(_ info: DirectPlaybackInfo) -> Bool
    func play(_ info: DirectPlaybackInfo, client: DirectPlaybackClient, context: PlaybackContext)
}
