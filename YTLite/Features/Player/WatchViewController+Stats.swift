import AVFoundation
import UIKit

// MARK: - Stats for nerds

extension WatchViewController {
    func toggleStatsOverlay() {
        if statsOverlay != nil {
            hideStatsOverlay()
        } else {
            showStatsOverlay()
        }
    }

    func hideStatsOverlay() {
        statsOverlay?.stop()
        statsOverlay?.removeFromSuperview()
        statsOverlay = nil
    }

    private func showStatsOverlay() {
        guard let playerView = videoPlayerView else {
            return
        }
        let overlay = StatsOverlayView()
        overlay.provider = { [weak self] in
            self?.statsText() ?? ""
        }
        overlay.onClose = { [weak self] in
            self?.hideStatsOverlay()
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        playerView.addSubview(overlay)
        let safeArea = playerView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(
                equalTo: safeArea.topAnchor, constant: 8
            ),
            overlay.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor, constant: 8
            ),
            overlay.trailingAnchor.constraint(
                lessThanOrEqualTo: safeArea.trailingAnchor, constant: -8
            )
        ])
        statsOverlay = overlay
        overlay.start()
    }

    // MARK: - Text assembly

    private func statsText() -> String {
        let source = playbackFacade.activeVideoSource
        let item = videoPlayerView?.player?.currentItem
        var rows = [
            row(
                "视频ID/来源",
                "\(playbackFacade.currentVideoId ?? "?")"
                    + " / \(kindName(source?.kind))"
            ),
            row("视口/丢帧", viewportValue(dropped: item)),
            row("当前/已选", resolutionValue(item, source: source))
        ]
        if let codecs = source?.currentCodecs {
            rows.append(row("编码", codecs))
        }
        rows.append(row("连接速度", speedValue(item)))
        rows.append(row("网络活动", transferredValue(item)))
        rows.append(row("缓冲健康", bufferValue(item)))
        return rows.joined(separator: "\n")
    }

    private func row(_ title: String, _ value: String) -> String {
        title.padding(toLength: 19, withPad: " ", startingAt: 0) + value
    }

    private func kindName(_ kind: VideoSourceKind?) -> String {
        switch kind {
        case .androidVR:
            return "android_vr"
        case .mwebPot:
            return "mweb+pot"
        case .progressive:
            return "progressive"
        case .auto:
            return "auto"
        case nil:
            return "?"
        }
    }

    private func viewportValue(dropped item: AVPlayerItem?) -> String {
        let playerView = videoPlayerView
        let size = playerView?.bounds.size ?? .zero
        let scale = playerView?.window?.screen.scale ?? UIScreen.main.scale
        let droppedFrames = (item?.accessLog()?.events ?? [])
            .reduce(0) { $0 + max(0, $1.numberOfDroppedVideoFrames) }
        return String(
            format: "%.0fx%.0f*%.2f / %d dropped",
            size.width,
            size.height,
            scale,
            droppedFrames
        )
    }

    /// Decoder-reported size (the truth) vs the picked ladder tier.
    private func resolutionValue(
        _ item: AVPlayerItem?, source: VideoSource?
    ) -> String {
        let size = item?.presentationSize ?? .zero
        let fps = source?.currentQuality?.fps.map { "@\($0)" } ?? ""
        let actual = size == .zero
            ? "?"
            : String(format: "%.0fx%.0f%@", size.width, size.height, fps)
        return "\(actual) / \(source?.currentQuality?.label ?? "?")"
    }

    private func speedValue(_ item: AVPlayerItem?) -> String {
        guard let bitrate = item?.accessLog()?.events.last?.observedBitrate,
              bitrate > 0 else {
            return "?"
        }
        return "\(Int(bitrate / 1_000)) Kbps"
    }

    private func transferredValue(_ item: AVPlayerItem?) -> String {
        let bytes = (item?.accessLog()?.events ?? [])
            .reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) }
        return String(
            format: "%.1f MB total", Double(bytes) / 1_048_576
        )
    }

    private func bufferValue(_ item: AVPlayerItem?) -> String {
        guard let item else {
            return "?"
        }
        let now = CMTimeGetSeconds(item.currentTime())
        let bufferedEnd = item.loadedTimeRanges
            .map { $0.timeRangeValue }
            .map { CMTimeGetSeconds($0.start) + CMTimeGetSeconds($0.duration) }
            .filter { $0 >= now }
            .max()
        guard let bufferedEnd else {
            return "0.0 s"
        }
        return String(format: "%.1f s", bufferedEnd - now)
    }
}
