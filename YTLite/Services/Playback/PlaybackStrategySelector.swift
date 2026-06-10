import Foundation

/// Selects the first applicable PlaybackStrategy for a given DirectPlaybackInfo.
/// Priority order:
///   1. HLS manifest (native AVPlayer — fastest, preferred)
///   2. Generated HLS from DASH SIDX (adaptive quality 360p–1080p)
///   3. Progressive (360p fallback when adaptive is unavailable)
enum PlaybackStrategySelector {
    private static let strategies: [PlaybackStrategy] = [
        HLSPlaybackStrategy(),
        GeneratedHLSPlaybackStrategy(),
        ProgressiveUpgradeStrategy()
    ]

    /// Returns the first strategy that can handle the given info, or nil if none apply.
    static func select(
        for info: DirectPlaybackInfo
    ) -> PlaybackStrategy? {
        let selected = strategies.first { $0.canHandle(info) }
        let name = selected.map {
            String(describing: type(of: $0))
        } ?? "none"
        AppLog.player("Strategy selected: \(name)")
        return selected
    }
}
