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

/// Drives source-based playback: picks a `VideoSource` via the factory, loads
/// it, and hands the prepared item to the `PlaybackContext` (player shell).
final class PlaybackFacade {
    weak var context: PlaybackContext?
    /// The active source — owns stream resolution and quality selection.
    var activeVideoSource: VideoSource?
    let watchtimeTracker = WatchtimeTracker()
    var currentVideoId: String?
    weak var currentApiClient: WatchService?
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
        let source = DefaultVideoSourceFactory(apiClient: apiClient)
            .make(kind: PlaybackSource.selected.sourceKind)
        activeVideoSource = source
        context?.updateStatusLabel("解析流...")
        source.loadPlayback(
            videoId: videoId,
            cancellation: cancellationToken
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      !cancellationToken.isCancelled else {
                    return
                }
                self.handlePrepared(result)
            }
        }
    }

    private func handlePrepared(
        _ result: Result<PreparedPlayback, Error>
    ) {
        switch result {
        case .success(let prepared):
            let kind = activeVideoSource?.kind
            let count = activeVideoSource?.availableQualities.count ?? 0
            AppLog.player(
                "source \(String(describing: kind)) playing, \(count) qualities"
            )
            context?.attachPrepared(prepared, resumeAt: nil)
            fetchWatchtimeAndTrack()
        case .failure(let error):
            AppLog.player("source playback failed: \(error)")
            context?.showPlaybackError("播放失败.")
        }
    }

    func reset() {
        activeVideoSource = nil
        watchtimeTracker.stop()
        currentVideoId = nil
        currentApiClient = nil
    }
}
