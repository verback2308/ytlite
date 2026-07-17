import AVFoundation
import Foundation

// MARK: - VideoSource contracts
//
// One interface every video source implements. A source owns its ENTIRE
// concern: resolving a playable stream AND its quality options (get/set). No
// source-specific branching leaks into the player shell or the UI — the view
// controller talks only to `VideoSource`.

/// Identifies a source; maps 1:1 from the user-facing `PlaybackSource` setting.
enum VideoSourceKind {
    /// Composite strategy: android_vr first, mweb+pot on failure. Only ever a
    /// factory input — a playing source always reports a concrete kind.
    case auto
    case androidVR
    case progressive
    case mwebPot
}

/// A selectable quality level, expressed source-agnostically.
struct VideoQuality: Equatable {
    let id: String
    let label: String
    let height: Int?
    let fps: Int?
}

/// A ready-to-play result handed back to the player shell. The shell attaches
/// `item` and retains `resourceLoader` for the item's lifetime.
struct PreparedPlayback {
    let item: AVPlayerItem
    let resourceLoader: AVAssetResourceLoaderDelegate?
    let captions: [SubtitleTrack]
    let duration: Double?

    init(
        item: AVPlayerItem,
        resourceLoader: AVAssetResourceLoaderDelegate? = nil,
        captions: [SubtitleTrack] = [],
        duration: Double? = nil
    ) {
        self.item = item
        self.resourceLoader = resourceLoader
        self.captions = captions
        self.duration = duration
    }
}

/// A single video source: resolves a stream and owns its quality selection.
protocol VideoSource: AnyObject {
    var kind: VideoSourceKind { get }
    /// Whether this source exposes a quality menu at all.
    var supportsQualitySelection: Bool { get }
    /// Qualities available for the currently loaded video (empty until loaded).
    var availableQualities: [VideoQuality] { get }
    /// The active quality, if any.
    var currentQuality: VideoQuality? { get }
    /// Active codec/itag pair for the stats overlay, when the source knows it.
    var currentCodecs: String? { get }

    /// Resolves the video and produces a ready-to-play result.
    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    )

    /// Switches quality; the source rebuilds playback its own way.
    func selectQuality(
        _ quality: VideoQuality,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    )
}

extension VideoSource {
    var currentCodecs: String? { nil }
}

/// Creates the right `VideoSource` for a kind (abstract factory).
protocol VideoSourceFactory {
    func make(kind: VideoSourceKind) -> VideoSource
}
