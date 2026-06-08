import AVFoundation
import UIKit

enum PlaybackBufferPolicy {
    static let defaultForwardBufferDuration: TimeInterval = 20.0
    static let backgroundBufferDuration: TimeInterval = 30.0

    static func configure(
        item: AVPlayerItem,
        forwardBufferDuration: TimeInterval = defaultForwardBufferDuration
    ) {
        item.preferredForwardBufferDuration = forwardBufferDuration
    }

    static func configure(
        player: AVPlayer,
        waitsToMinimizeStalling: Bool = true
    ) {
        player.automaticallyWaitsToMinimizeStalling =
            waitsToMinimizeStalling
    }
}

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

enum BackgroundPlaybackMode {
    case inline
    case audioOnlyHLS
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
    var backgroundAudioItem: AVPlayerItem?
    var backgroundRestoreTime: CMTime = .zero
    var backgroundEnteredAt: Date?
    var backgroundPlaybackMode: BackgroundPlaybackMode = .inline
    var playlistSwitchBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var activeDirectPlaybackClient: DirectPlaybackClient = .androidVR
    var backgroundAudioObservation: NSKeyValueObservation?
    let watchtimeTracker = WatchtimeTracker()
    var currentVideoId: String?
    weak var currentApiClient: WatchService?

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
        currentVideoId = videoId
        currentApiClient = apiClient
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
        backgroundAudioObservation = nil
        backgroundAudioItem = nil
        hlsPlaylistLoader = nil
        activePlaybackInfo = nil
        activeVideoFormat = nil
        activePlaybackHeaders = [:]
        backgroundRestoreTime = .zero
        backgroundEnteredAt = nil
        backgroundPlaybackMode = .inline
        activeDirectPlaybackClient = .androidVR
        watchtimeTracker.stop()
        currentVideoId = nil
        currentApiClient = nil
    }
}
