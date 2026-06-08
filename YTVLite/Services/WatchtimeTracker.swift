import Foundation

/// Records YouTube watch history by pinging
/// playbackTracking URLs from an authenticated TV player
/// response, using the same parameters as yt-dlp
/// --mark-watched.
final class WatchtimeTracker {
    private static let pingDelay: TimeInterval = 30
    private let cpn: String = WatchtimeTracker.makeCPN()
    private var pingTimer: Timer?
    private var urls: WatchtimeURLs?

    private static func makeCPN() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz"
            + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        return String(
            (0..<16).compactMap { _ in
                Array(chars).randomElement()
            }
        )
    }

    func start(urls: WatchtimeURLs) {
        stop()
        self.urls = urls
        sendPlaybackPing(urls: urls)
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.pingTimer = Timer.scheduledTimer(
                withTimeInterval: Self.pingDelay,
                repeats: false
            ) { [weak self] _ in
                self?.sendWatchtimePing()
            }
        }
        AppLog.log("Watchtime", "tracker started (TV)")
    }

    func stop() {
        pingTimer?.invalidate()
        pingTimer = nil
        urls = nil
    }

    private func sendPlaybackPing(urls: WatchtimeURLs) {
        let len = durationParam(urls.duration)
        let extra = "ver=2&cpn=\(cpn)&cmt=\(len)&el=detailpage"
        fire(baseURL: urls.playbackURL, extra: extra)
    }

    private func sendWatchtimePing() {
        guard let urls else {
            return
        }
        let len = durationParam(urls.duration)
        let extra = "ver=2&cpn=\(cpn)"
            + "&cmt=\(len)&el=detailpage"
            + "&st=0&et=\(len)"
        fire(baseURL: urls.watchtimeURL, extra: extra)
        AppLog.log("Watchtime", "watchtime ping sent")
    }

    private func durationParam(
        _ duration: Double?
    ) -> String {
        let len = max(1.0, (duration ?? 1.5)) - 1.0
        return String(format: "%.3f", len)
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
