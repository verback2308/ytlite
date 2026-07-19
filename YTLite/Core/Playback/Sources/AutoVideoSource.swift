import Foundation

/// Composite "Auto" strategy source: tries a fast primary source first and, on
/// any load failure, transparently retries with a fallback source. Quality
/// state is delegated to whichever inner source is active, so the player shell
/// keeps talking to a single `VideoSource`.
///
/// Audio tracks (dubs) are the in-place source switch this composite exists
/// for. The dub probe starts TOGETHER with the primary load: when the
/// auto-dub preference decides a dub before the primary finishes, the load
/// commits to the fallback (mweb) starting directly on that track and the
/// primary result is discarded — no original-audio flash. When the primary
/// wins the race, the shell performs a visible switch instead; picking a dub
/// from the menu rebuilds on the fallback and makes it the active source.
final class AutoVideoSource: VideoSource {
    private static let noTrackError = NSError(
        domain: "AutoVideoSource",
        code: 0,
        userInfo: [NSLocalizedDescriptionKey: "Audio track unavailable"]
    )

    // Non-private for the auto-dub race extension (AutoVideoSource+AutoDub).
    let primary: VideoSource
    private let makeFallback: () -> VideoSource
    /// The inner source currently answering playback/quality questions.
    var active: VideoSource
    /// Lazily created fallback instance — shared between the background dub
    /// probe and a later switch, so the probed /player info is built on
    /// directly instead of being fetched twice.
    var fallback: VideoSource?
    /// The primary result once it lands — kept even after committing to a
    /// dub start so a failed dub build can still deliver the primary.
    var primaryOutcome: Result<PreparedPlayback, Error>?
    /// Probe decided a dub before the primary finished: the fallback owns
    /// the load completion and the primary result is discarded on arrival.
    var committedToDub = false
    /// The committed dub build failed — deliver the primary result instead.
    var dubStartFailed = false

    var kind: VideoSourceKind { active.kind }
    var supportsQualitySelection: Bool { active.supportsQualitySelection }
    var availableQualities: [VideoQuality] { active.availableQualities }
    var currentQuality: VideoQuality? { active.currentQuality }
    var currentCodecs: String? { active.currentCodecs }
    var supportsAudioTrackSelection: Bool { availableAudioTracks.count > 1 }
    /// The active source's tracks, or the fallback's probed ones while the
    /// primary (which never lists dubs) is playing.
    var availableAudioTracks: [AudioTrack] {
        let tracks = active.availableAudioTracks
        return tracks.isEmpty ? (fallback?.availableAudioTracks ?? []) : tracks
    }
    /// While the primary plays, the fallback's probe state answers — it
    /// marks the ORIGINAL track current, which is what the primary
    /// (android_vr) always plays.
    var currentAudioTrack: AudioTrack? {
        active.currentAudioTrack ?? fallback?.currentAudioTrack
    }

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
        primaryOutcome = nil
        committedToDub = false
        dubStartFailed = false
        probeAudioTracksEarly(
            videoId: videoId, cancellation: cancellation, completion: completion
        )
        primary.loadPlayback(
            videoId: videoId, cancellation: cancellation
        ) { [weak self] result in
            // Probe and primary complete on different queues; all composite
            // state transitions happen on main.
            DispatchQueue.main.async {
                self?.handlePrimaryResult(
                    result,
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

    /// Delegates when the active source owns the track; otherwise rebuilds on
    /// the probed fallback and promotes it to active — only on success, so a
    /// failed switch leaves the current playback untouched.
    func selectAudioTrack(
        _ track: AudioTrack,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        if active.availableAudioTracks.contains(track) {
            active.selectAudioTrack(track, completion: completion)
            return
        }
        guard let fallback,
              fallback.availableAudioTracks.contains(track) else {
            completion(.failure(Self.noTrackError))
            return
        }
        AppLog.player(
            "auto: switching to \(fallback.kind) for audio track \(track.id)"
        )
        fallback.selectAudioTrack(track) { [weak self] result in
            if case .success = result {
                self?.active = fallback
            }
            completion(result)
        }
    }

    // MARK: - Internal (shared with the auto-dub extension)

    /// Creates and retains the shared fallback instance — the probe and a
    /// later switch/load must build on the same one.
    func makeFallbackShared() -> VideoSource {
        let source = fallback ?? makeFallback()
        fallback = source
        return source
    }

    func loadFallback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        let source = makeFallbackShared()
        active = source
        source.loadPlayback(
            videoId: videoId,
            cancellation: cancellation,
            completion: completion
        )
    }
}
