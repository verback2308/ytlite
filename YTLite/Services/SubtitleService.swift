import Foundation

final class SubtitleService {
    static let shared = SubtitleService()

    private var cache: [URL: [SubtitleCue]] = [:]
    private var pending: [URL: [(([SubtitleCue]) -> Void)]] = [:]
    private let queue = DispatchQueue(
        label: "com.verback.YTLite.subtitles"
    )

    private init() {}

    func load(
        track: SubtitleTrack,
        completion: @escaping ([SubtitleCue]) -> Void
    ) {
        // Append format=vtt to get WebVTT
        guard var comps = URLComponents(
            url: track.url,
            resolvingAgainstBaseURL: false
        ) else {
            completion([])
            return
        }
        var queryItems = comps.queryItems ?? []
        // Replace existing fmt param (YouTube default is srv3/XML)
        queryItems.removeAll { $0.name == "fmt" }
        queryItems.append(
            URLQueryItem(name: "fmt", value: "vtt")
        )
        comps.queryItems = queryItems
        guard let url = comps.url else {
            completion([])
            return
        }
        queue.async { [weak self] in
            self?.fetchCached(url: url, completion: completion)
        }
    }

    private func fetchCached(
        url: URL,
        completion: @escaping ([SubtitleCue]) -> Void
    ) {
        if let cached = cache[url] {
            DispatchQueue.main.async { completion(cached) }
            return
        }
        if pending[url] != nil {
            pending[url]?.append(completion)
            return
        }
        pending[url] = [completion]
        performFetch(url: url)
    }

    private func performFetch(url: URL) {
        let task = URLSession.shared.dataTask(
            with: url
        ) { [weak self] data, response, _ in
            let http = (response as? HTTPURLResponse)?.statusCode ?? 0
            self?.handleFetchResponse(
                url: url, data: data, status: http
            )
        }
        task.resume()
    }

    private func handleFetchResponse(
        url: URL,
        data: Data?,
        status: Int
    ) {
        let cues: [SubtitleCue]
        if let data,
           let text = String(data: data, encoding: .utf8) {
            cues = VTTParser.parse(text)
        } else {
            cues = []
        }
        queue.async { [weak self] in
            self?.cache[url] = cues
            let callbacks = self?.pending.removeValue(forKey: url) ?? []
            DispatchQueue.main.async {
                callbacks.forEach { $0(cues) }
            }
        }
    }

    func clearCache() {
        queue.async { [weak self] in
            self?.cache = [:]
        }
    }
}
