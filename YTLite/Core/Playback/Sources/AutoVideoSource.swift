import Foundation

/// Composite "Auto" strategy source: tries a fast primary source first and, on
/// any load failure, transparently retries with a fallback source. Quality
/// state is delegated to whichever inner source is active, so the player shell
/// keeps talking to a single `VideoSource`.
///
/// This is also the extension point for future in-place source switches (e.g.
/// re-loading via the fallback with a user-picked audio track): both sources
/// are owned here, so swapping `active` and reloading stays a local operation.
final class AutoVideoSource: VideoSource {
    private let primary: VideoSource
    private let makeFallback: () -> VideoSource
    /// The inner source currently answering playback/quality questions.
    private var active: VideoSource

    var kind: VideoSourceKind { active.kind }
    var supportsQualitySelection: Bool { active.supportsQualitySelection }
    var availableQualities: [VideoQuality] { active.availableQualities }
    var currentQuality: VideoQuality? { active.currentQuality }
    var currentCodecs: String? { active.currentCodecs }

    init(primary: VideoSource, makeFallback: @escaping () -> VideoSource) {
        self.primary = primary
        self.makeFallback = makeFallback
        active = primary
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        active = primary
        primary.loadPlayback(
            videoId: videoId, cancellation: cancellation
        ) { [weak self] result in
            guard let self else {
                return
            }
            switch result {
            case .success:
                completion(result)
            case .failure(let error):
                guard cancellation?.isCancelled != true else {
                    completion(result)
                    return
                }
                AppLog.player(
                    "auto: \(self.primary.kind) failed (\(error)), falling back"
                )
                self.loadFallback(
                    videoId: videoId,
                    cancellation: cancellation,
                    completion: completion
                )
            }
        }
    }

    func selectQuality(
        _ quality: VideoQuality,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        active.selectQuality(quality, completion: completion)
    }

    // MARK: - Private

    private func loadFallback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let fallback = makeFallback()
        active = fallback
        fallback.loadPlayback(
            videoId: videoId,
            cancellation: cancellation,
            completion: completion
        )
    }
}
