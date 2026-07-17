import AVFoundation
import Foundation

/// Shared live-stream machinery for `VideoSource`s: live streams have no DASH
/// SIDX ladder, so quality comes from the HLS multivariant playlist instead.
/// "Auto" plays the playlist itself (AVPlayer's ABR); pinning a quality serves
/// a playlist filtered to that one variant through the custom-scheme loader —
/// the variant's media playlist and segments load over https as usual, so
/// live reloads never touch the loader.
final class LiveHLSPlayback {
    static let autoQuality = VideoQuality(
        id: "live-auto", label: "Auto", height: nil, fps: nil
    )

    /// "Auto" + the parsed variants; empty until a playlist loads.
    private(set) var qualities: [VideoQuality] = []
    /// What `load` started playback on — the user's default-quality cap
    /// applied to the variant ladder, or Auto without a cap.
    private(set) var startQuality: VideoQuality = LiveHLSPlayback.autoQuality
    private var playlist: (text: String, url: URL)?
    private var variants: [LiveHLSVariant] = []
    private let resolver: HLSStreamResolver

    /// Whether live HLS is what's playing — owning sources route quality
    /// selection here while active.
    var isActive: Bool { playlist != nil }

    init(resolver: HLSStreamResolver = .shared) {
        self.resolver = resolver
    }

    func reset() {
        playlist = nil
        variants = []
        qualities = []
        startQuality = Self.autoQuality
    }

    /// Fetches and parses the multivariant playlist, then hands back playback
    /// on "Auto". Always succeeds — a failed fetch just means no picker.
    func load(
        url: URL,
        info: DirectPlaybackInfo,
        completion: @escaping (PreparedPlayback) -> Void
    ) {
        resolver.fetchText(url: url) { [weak self] result in
            guard let self else {
                return
            }
            if case .success(let text) = result {
                self.variants = LiveHLSVariants.parse(playlist: text, baseURL: url)
                if !self.variants.isEmpty {
                    self.playlist = (text, url)
                    self.qualities =
                        [Self.autoQuality] + self.variants.map { $0.quality }
                }
            }
            AppLog.player("liveHLS: \(self.variants.count) variants")
            completion(self.initialPlayback(url: url, info: info))
        }
    }

    /// Builds playback for a picked quality; nil when the quality is unknown
    /// or no live playlist is active.
    func prepared(
        for quality: VideoQuality, info: DirectPlaybackInfo
    ) -> PreparedPlayback? {
        guard let playlist else {
            return nil
        }
        if quality == Self.autoQuality {
            return prepared(item: AVPlayerItem(url: playlist.url), info: info)
        }
        guard let variant = variants.first(where: { $0.quality == quality }),
              let pinned = pinnedItem(variant: variant, playlist: playlist) else {
            return nil
        }
        return PreparedPlayback(
            item: pinned.item,
            resourceLoader: pinned.loader,
            captions: info.captionTracks,
            duration: info.duration
        )
    }

    // MARK: - Private

    /// Applies the user's default-quality setting to the initial pick: no cap
    /// ("Auto"), no variants, or a failed pinned build all start ABR playback.
    private func initialPlayback(
        url: URL, info: DirectPlaybackInfo
    ) -> PreparedPlayback {
        startQuality = Self.autoQuality
        guard let capped = cappedQuality(maxHeight: VideoQualityStore.maxHeight),
              let pinned = prepared(for: capped, info: info) else {
            return prepared(item: AVPlayerItem(url: url), info: info)
        }
        startQuality = capped
        AppLog.player("liveHLS: starting at \(capped.label) (default-quality cap)")
        return pinned
    }

    /// Best variant within the height cap; the ladder is sorted descending,
    /// so the first fit wins. A cap below the whole ladder takes the lowest
    /// variant rather than ignoring the setting.
    private func cappedQuality(maxHeight: Int?) -> VideoQuality? {
        guard let maxHeight, !variants.isEmpty else {
            return nil
        }
        let fitting = variants.first { ($0.quality.height ?? 0) <= maxHeight }
        return (fitting ?? variants.last)?.quality
    }

    private func prepared(
        item: AVPlayerItem, info: DirectPlaybackInfo
    ) -> PreparedPlayback {
        PreparedPlayback(
            item: item, captions: info.captionTracks, duration: info.duration
        )
    }

    private func pinnedItem(
        variant: LiveHLSVariant,
        playlist: (text: String, url: URL)
    ) -> (item: AVPlayerItem, loader: HLSPlaylistLoader)? {
        guard let playlistURL = URL(
            string: "\(HLSGenerator.scheme)://live-main.m3u8"
        ) else {
            return nil
        }
        let filtered = LiveHLSVariants.manifest(
            keeping: variant, playlist: playlist.text, baseURL: playlist.url
        )
        let loader = HLSPlaylistLoader()
        loader.register(path: "live-main.m3u8", content: filtered)
        let asset = AVURLAsset(url: playlistURL)
        asset.resourceLoader.setDelegate(loader, queue: loader.loaderQueue)
        return (AVPlayerItem(asset: asset), loader)
    }
}
