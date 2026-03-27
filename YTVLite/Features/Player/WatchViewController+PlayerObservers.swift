import AVFoundation
import UIKit

extension WatchViewController {
    func startObservingPlayerItem(
        _ item: AVPlayerItem
    ) {
        statusObservation = item.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] observed, _ in
            self?.handlePlayerItemStatusChange(observed)
        }
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(playerItemDidFailToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
        nc.addObserver(
            self,
            selector: #selector(playerItemNewErrorLogEntry(_:)),
            name: .AVPlayerItemNewErrorLogEntry,
            object: item
        )
        nc.addObserver(
            self,
            selector: #selector(playerItemDidPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    func stopObservingPlayerItem(
        _ item: AVPlayerItem
    ) {
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        nc.removeObserver(self, name: .AVPlayerItemNewErrorLogEntry, object: item)
        nc.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        statusObservation?.invalidate()
        statusObservation = nil
    }

    func handlePlayerItemStatusChange(
        _ item: AVPlayerItem
    ) {
        switch item.status {
        case .readyToPlay:
            let dur = CMTimeGetSeconds(item.duration)
            let tracks = item.tracks
                .map {
                    $0.assetTrack?.mediaType
                        .rawValue ?? "?"
                }
                .joined(separator: ",")
            AppLog.player(
                "player item ready:"
                    + " duration=\(dur)s"
                    + " tracks=[\(tracks)]"
            )
        case .failed:
            logPlaybackFailure(item)
        case .unknown:
            AppLog.player("player item status unknown")
        @unknown default:
            AppLog.player("player item status unexpected")
        }
    }

    func logPlaybackFailure(_ item: AVPlayerItem) {
        let nsError = item.error as NSError?
        let desc = item.error?.localizedDescription ?? "unknown"
        let domain = nsError?.domain ?? "nil"
        let code = nsError?.code ?? 0
        AppLog.player(
            "player item FAILED: \(desc)"
                + " domain=\(domain) code=\(code)"
        )
        guard let underlying = nsError?
            .userInfo[NSUnderlyingErrorKey]
            as? NSError else {
            return
        }
        AppLog.player(
            "underlying error:"
                + " \(underlying.domain)"
                + " code=\(underlying.code)"
                + " \(underlying.localizedDescription)"
        )
    }

    @objc
    func playerItemDidFailToPlayToEnd(
        _ note: Notification
    ) {
        let errorKey =
            AVPlayerItemFailedToPlayToEndTimeErrorKey
        let err =
            (note.userInfo?[errorKey] as? Error)?
                .localizedDescription ?? "unknown"
        AppLog.player(
            "player item failed to end: \(err)"
        )
    }

    @objc
    func playerItemDidPlayToEnd(
        _ notification: Notification
    ) {
        guard let nextVideo =
            watchPage?.nextVideo else {
            return
        }
        showAutoplayOverlay(for: nextVideo)
    }

    @objc
    func playerItemNewErrorLogEntry(
        _ note: Notification
    ) {
        guard let item =
            note.object as? AVPlayerItem,
              let events = item.errorLog()?.events,
              let last = events.last else {
            AppLog.player(
                "player item new error log entry"
            )
            return
        }
        AppLog.player(
            "player error log:"
                + " domain=\(last.errorDomain ?? "nil"),"
                + " code=\(last.errorStatusCode),"
                + " comment=\(last.errorComment ?? "nil"),"
                + " uri=\(last.uri ?? "nil")"
        )
    }

    func showPlaybackError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.playerSpinner.stopAnimating()
            self?.playerStatusLabel.text =
                "Playback error: \(message)"
            self?.playerStatusLabel.textColor =
                .systemRed
        }
    }
}
