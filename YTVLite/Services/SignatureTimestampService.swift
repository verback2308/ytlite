import Foundation

/// Fetches and caches the YouTube player signatureTimestamp (STS).
/// Required for TVHTML5 /player requests to return playbackTracking URLs.
/// Extracted from YouTube's ytcfg ("STS":NNNNN) — one HTTP request,
/// no player JS parsing needed. Value changes ~weekly.
final class SignatureTimestampService {
    static let shared = SignatureTimestampService()

    private let tsKey = "SignatureTimestamp.value"
    private let dateKey = "SignatureTimestamp.fetchedAt"
    private let ttl: TimeInterval = 7 * 24 * 3_600
    private let queue = DispatchQueue(
        label: "com.ytvlite.sig-ts",
        attributes: .concurrent
    )

    private var _cached: Int?
    private var cached: Int? {
        get { queue.sync { _cached } }
        set { queue.async(flags: .barrier) { self._cached = newValue } }
    }

    init() {
        loadFromDefaults()
    }

    func fetch(completion: @escaping (Int?) -> Void) {
        if let ts = cached {
            completion(ts)
            return
        }
        fetchFromNetwork(completion: completion)
    }

    // MARK: - Private

    private func loadFromDefaults() {
        let defaults = UserDefaults.standard
        guard let ts = defaults.object(forKey: tsKey) as? Int,
              let date = defaults.object(forKey: dateKey) as? Date,
              Date().timeIntervalSince(date) < ttl
        else {
            return
        }
        _cached = ts
    }

    private func saveToDefaults(_ ts: Int) {
        let defaults = UserDefaults.standard
        defaults.set(ts, forKey: tsKey)
        defaults.set(Date(), forKey: dateKey)
    }

    private func fetchFromNetwork(
        completion: @escaping (Int?) -> Void
    ) {
        // YouTube embeds signatureTimestamp as "STS":NNNNN in ytcfg
        // on both the main page and /tv — one request is enough.
        let sources = [
            "https://www.youtube.com/",
            "https://www.youtube.com/tv"
        ]
        fetchSTS(from: sources, index: 0, completion: completion)
    }

    private func fetchSTS(
        from sources: [String],
        index: Int,
        completion: @escaping (Int?) -> Void
    ) {
        guard index < sources.count,
              let url = URL(string: sources[index])
        else {
            AppLog.log("SigTS", "fetch failed — no STS found")
            completion(nil)
            return
        }
        let task = URLSession.shared.dataTask(
            with: url
        ) { [weak self] data, _, _ in
            guard let self else {
                completion(nil)
                return
            }
            if let data,
               let html = String(data: data, encoding: .utf8),
               let ts = self.extractSTS(from: html) {
                AppLog.log("SigTS", "signatureTimestamp=\(ts)")
                self.cached = ts
                self.saveToDefaults(ts)
                completion(ts)
            } else {
                self.fetchSTS(
                    from: sources,
                    index: index + 1,
                    completion: completion
                )
            }
        }
        task.resume()
    }

    private func extractSTS(from html: String) -> Int? {
        for pattern in ["\"STS\":(\\d+)", "\"sts\":(\\d+)"] {
            guard let range = html.range(
                of: pattern,
                options: .regularExpression
            ) else {
                continue
            }
            let matched = String(html[range])
            if let last = matched.components(
                separatedBy: ":"
            ).last, let ts = Int(last) {
                return ts
            }
        }
        return nil
    }
}
