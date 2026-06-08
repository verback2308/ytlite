import Foundation

/// Records YouTube watch history by pinging
/// playbackTracking URLs from an authenticated TV player
/// response, using the same parameters as yt-dlp
/// --mark-watched.
final class WatchtimeTracker {
    private static let pingInterval: TimeInterval = 15
    private let cpn: String = WatchtimeTracker.makeCPN()
    private var pingTimer: Timer?
    private var urls: WatchtimeURLs?
    private var videoId: String?
    private var sessionStart: Date?

    /// Provides current playback position (seconds).
    /// Set by the host view controller before or after start().
    var timeProvider: (() -> TimeInterval)?

    private static func makeCPN() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        return String(
            (0..<16).compactMap { _ in
                Array(chars).randomElement()
            }
        )
    }

    func start(videoId: String, urls: WatchtimeURLs) {
        stop()
        self.videoId = videoId
        self.urls = urls
        self.sessionStart = Date()
        sendPlaybackPing(urls: urls)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.pingTimer = Timer.scheduledTimer(
                withTimeInterval: Self.pingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.sendWatchtimePing()
            }
        }
        AppLog.log("Watchtime", "tracker started \(videoId)")
    }

    func stop() {
        if urls != nil {
            sendFinalPing()
        }
        pingTimer?.invalidate()
        pingTimer = nil
        urls = nil
        videoId = nil
        sessionStart = nil
    }

    // MARK: - Private

    private func currentPosition() -> TimeInterval {
        timeProvider?() ?? 0
    }

    private func sendPlaybackPing(urls: WatchtimeURLs) {
        let pos = currentPosition()
        let extra = "ver=2&cpn=\(cpn)&cmt=\(fmt(pos))&el=detailpage"
        fire(baseURL: urls.playbackURL, extra: extra)
    }

    private func sendWatchtimePing() {
        guard let urls else {
            return
        }
        let pos = currentPosition()
        let extra = "ver=2&cpn=\(cpn)"
            + "&cmt=\(fmt(pos))&el=detailpage"
            + "&st=0&et=\(fmt(pos))"
        fire(baseURL: urls.watchtimeURL, extra: extra)
        updateLocalProgress(position: pos, urls: urls)
        AppLog.log(
            "Watchtime",
            "watchtime ping sent pos=\(Int(pos))s"
        )
    }

    private func sendFinalPing() {
        guard let urls else {
            return
        }
        let pos = currentPosition()
        guard pos > 0 else {
            return
        }
        let extra = "ver=2&cpn=\(cpn)"
            + "&cmt=\(fmt(pos))&el=detailpage"
            + "&st=0&et=\(fmt(pos))"
        fire(baseURL: urls.watchtimeURL, extra: extra)
        updateLocalProgress(position: pos, urls: urls)
        AppLog.log(
            "Watchtime",
            "final ping pos=\(Int(pos))s"
        )
    }

    private func updateLocalProgress(
        position: TimeInterval,
        urls: WatchtimeURLs
    ) {
        guard let videoId,
              let duration = urls.duration,
              duration > 0
        else {
            return
        }
        WatchProgressStore.shared.setProgress(
            videoId: videoId,
            position: position,
            duration: duration
        )
    }

    private func fmt(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", max(0, seconds))
    }

    private func fire(baseURL: String, extra: String) {
        let sep = baseURL.contains("?") ? "&" : "?"
        let urlStr = baseURL + sep + extra
        guard let url = URL(string: urlStr) else {
            return
        }
        OAuthClient.shared.validToken { result in
            var req = URLRequest(url: url)
            if case .success(let token) = result {
                req.setValue(
                    "Bearer \(token)",
                    forHTTPHeaderField: "Authorization"
                )
            }
            let task = URLSession.shared.dataTask(
                with: req
            ) { _, response, _ in
                let code = (response as? HTTPURLResponse)?
                    .statusCode ?? 0
                AppLog.log("Watchtime", "ping response \(code)")
            }
            task.resume()
        }
    }
}
