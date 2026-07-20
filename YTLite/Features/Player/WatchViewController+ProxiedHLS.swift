import AVFoundation
import UIKit

// MARK: - Source-prepared playback

extension WatchViewController {
    /// Attaches an `AVPlayerItem` built by a `VideoSource`, retaining its
    /// resource loader (e.g. the HLS proxy) for the item's lifetime and
    /// publishing any caption tracks the source resolved.
    func attachPrepared(
        _ prepared: PreparedPlayback,
        resumeAt: CMTime? = nil
    ) {
        activeResourceLoader = prepared.resourceLoader
        if !prepared.captions.isEmpty {
            setCaptionTracks(prepared.captions)
        }
        attachPlayer(item: prepared.item)
        if let resumeAt, CMTimeGetSeconds(resumeAt) > 1 {
            videoPlayerView?.player?.seek(
                to: resumeAt,
                toleranceBefore: CMTime(seconds: 1, preferredTimescale: 1_000),
                toleranceAfter: CMTime(seconds: 1, preferredTimescale: 1_000)
            )
        }
    }

    /// Source-agnostic quality menu: renders `source.availableQualities` and
    /// applies the pick via `source.selectQuality`. No source-specific code.
    func showSourceQualityPicker(source: VideoSource) {
        let items = source.availableQualities.map { quality -> PlayerMenuItem in
            let isCurrent = quality == source.currentQuality
            let title = isCurrent ? "✓ \(quality.label)" : quality.label
            return PlayerMenuItem(title: title) { [weak self] in
                self?.selectSourceQuality(quality, source: source)
            }
        }
        presentPlayerMenu(title: "画质", items: items)
    }

    private func selectSourceQuality(
        _ quality: VideoQuality,
        source: VideoSource
    ) {
        guard quality != source.currentQuality else {
            return
        }
        let resumeTime = videoPlayerView?.player?.currentTime()
        playerStatusLabel.text = "加载中 \(quality.label)..."
        playerStatusLabel.isHidden = false
        source.selectQuality(quality) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let prepared):
                    self?.attachPrepared(prepared, resumeAt: resumeTime)
                case .failure:
                    self?.showPlaybackError("画质切换失败.")
                }
            }
        }
    }
}
