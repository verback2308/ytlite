import Foundation

/// Selects the first applicable PlaybackStrategy for a given DirectPlaybackInfo.
/// Priority order matches the original if/else chain in playDirectStream:
///   1. HLS manifest (native AVPlayer — fastest, preferred)
///   2. Generated HLS from DASH SIDX (instant 720p)
///   3. Progressive with background adaptive upgrade (360p fast start → 720p)
///   4. Adaptive only (video + audio, no progressive)
enum PlaybackStrategySelector {
    private static let strategies: [PlaybackStrategy] = [
        HLSPlaybackStrategy(),
        GeneratedHLSPlaybackStrategy(),
        ProgressiveUpgradeStrategy(),
        AdaptiveOnlyPlaybackStrategy()
    ]

    /// Returns the first strategy that can handle the given info, or nil if none apply.
    static func select(for info: DirectPlaybackInfo) -> PlaybackStrategy? {
        strategies.first { $0.canHandle(info) }
    }
}
