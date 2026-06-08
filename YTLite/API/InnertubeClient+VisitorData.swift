import Foundation

// MARK: - Playback & Visitor Data

extension InnertubeClient {
    static func extractVisitorData(from data: Data?) -> String? {
        guard
            let data,
            let html = String(data: data, encoding: .utf8),
            let start = html.range(of: "\"VISITOR_DATA\":\""),
            let end = html[start.upperBound...].range(of: "\"")
        else {
            return nil
        }
        let value = String(html[start.upperBound..<end.lowerBound])
        AppLog.innertube("extracted visitorData: \(value.prefix(30))...")
        return value
    }

    static func logPreflightCookies() {
        guard
            let base = URL(string: AppURLs.YouTube.base),
            let cookies = HTTPCookieStorage.shared.cookies(for: base)
        else {
            return
        }
        let names = cookies.map { $0.name }.joined(separator: ", ")
        AppLog.innertube("cookies after preflight: \(names)")
    }

    static func logVisitorCookies() {
        guard
            let base = URL(string: AppURLs.YouTube.base),
            let cookies = HTTPCookieStorage.shared.cookies(for: base),
            let vis = cookies.first(where: { $0.name == "VISITOR_INFO1_LIVE" }),
            let priv = cookies.first(where: { $0.name == "VISITOR_PRIVACY_METADATA" })
        else {
            return
        }
        AppLog.innertube(
            "VISITOR_INFO1_LIVE=\(vis.value.prefix(20))..." +
            " PRIVACY_METADATA=\(priv.value.prefix(20))..."
        )
    }

    func oauthPlayback(
        videoId: String,
        playbackClient: DirectPlaybackClient,
        poToken: String? = nil,
        cancellation: CancellationToken? = nil,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        OAuthClient.shared.validToken { [weak self] result in
            guard cancellation?.isCancelled != true else {
                return
            }
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                self?.executeDirectPlayback(
                    videoId: videoId,
                    client: playbackClient,
                    token: token,
                    poToken: poToken,
                    visitorData: nil,
                    cancellationToken: cancellation,
                    completion: completion
                )
            }
        }
    }

    func cookieAuthPlayback(
        videoId: String,
        playbackClient: DirectPlaybackClient,
        poToken: String? = nil,
        cancellation: CancellationToken? = nil,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        let dispatch: (String?) -> Void = { [weak self] visitorData in
            self?.executeDirectPlayback(
                videoId: videoId,
                client: playbackClient,
                token: "",
                poToken: poToken,
                visitorData: visitorData,
                cancellationToken: cancellation,
                completion: completion
            )
        }
        if let cached = session.visitorData {
            AppLog.innertube("visitorData cache hit for \(videoId)")
            dispatch(cached)
            return
        }
        fetchVisitorData(
            videoId: videoId,
            cancellationToken: cancellation
        ) { [weak self] visitorData in
            guard cancellation?.isCancelled != true else {
                return
            }
            if let visitorData {
                self?.session.visitorData = visitorData
            }
            dispatch(visitorData)
        }
    }

    func fetchVisitorData(
        videoId: String,
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (String?) -> Void
    ) {
        guard let request = buildVisitorRequest(videoId: videoId) else {
            completion(nil)
            return
        }
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                if (error as NSError).code != NSURLErrorCancelled {
                    AppLog.innertube(
                        "visitor data fetch failed: \(error.localizedDescription)"
                    )
                }
                completion(nil)
                return
            }
            Self.logPreflightCookies()
            let extracted = Self.extractVisitorData(from: data)
            if extracted == nil {
                Self.logVisitorCookies()
            }
            completion(extracted)
        }
        cancellationToken?.register(task)
        task.resume()
    }

    func buildVisitorRequest(videoId: String) -> URLRequest? {
        let base = "https://www.youtube.com/watch"
        let qs = "?v=\(videoId)&bpctr=9999999999&has_verified=1"
        guard let url = URL(string: base + qs) else {
            return nil
        }
        AppLog.innertube("fetching visitor data for \(videoId)...")
        var request = URLRequest(url: url)
        request.setValue(UserAgent.chromeDesktopPlayback, forHTTPHeaderField: HTTPHeader.userAgent)
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: HTTPHeader.accept
        )
        request.setValue("en-us,en;q=0.5", forHTTPHeaderField: HTTPHeader.acceptLanguage)
        setInitialCookies()
        return request
    }

    func setInitialCookies() {
        let pref: [HTTPCookiePropertyKey: Any] = [
            .name: "PREF", .value: "hl=en&tz=UTC",
            .domain: ".youtube.com", .path: "/"
        ]
        let socs: [HTTPCookiePropertyKey: Any] = [
            .name: "SOCS", .value: "CAI",
            .domain: ".youtube.com", .path: "/"
        ]
        if let cookie = HTTPCookie(properties: pref) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        if let cookie = HTTPCookie(properties: socs) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}
