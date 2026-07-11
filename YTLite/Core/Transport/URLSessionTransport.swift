import Foundation

/// The single `URLSession`-backed transport — the only place in the app that
/// touches `URLSession` (aside from `HLSPlaybackBuilder`'s AVFoundation byte
/// streaming, which is documented). Maps status codes onto `APIError` and
/// honours `CancellationToken`: a cancelled task silences its callback,
/// matching the previous `APIClient` behaviour.
final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    /// A session with no cookie storage — used for requests that opt out of
    /// cookies (`sendsCookies == false`). Guarantees the shared jar is never
    /// attached, independent of the per-request `httpShouldHandleCookies` flag.
    private let cookielessSession: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.cookielessSession = URLSession(configuration: config)
    }

    static func isCancelled(_ error: Error?) -> Bool {
        (error as NSError?)?.code == NSURLErrorCancelled
    }

    /// The transport reports transport-level failures only; interpreting the
    /// HTTP status is the caller's concern (some want 4xx as an error, others —
    /// e.g. SponsorBlock's 404 — treat it as a valid empty result).
    static func map(
        data: Data?,
        response: URLResponse?,
        error: Error?
    ) -> Result<HTTPResponse, Error> {
        if let error {
            return .failure(APIError.transport(error))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(APIError.invalidResponse)
        }
        return .success(
            HTTPResponse(
                status: http.statusCode,
                headers: stringHeaders(http.allHeaderFields),
                data: data ?? Data()
            )
        )
    }

    static func stringHeaders(
        _ raw: [AnyHashable: Any]
    ) -> [String: String] {
        raw.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
    }

    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    ) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.httpShouldHandleCookies = request.sendsCookies
        if let timeout = request.timeout {
            urlRequest.timeoutInterval = timeout
        }
        request.headers.forEach {
            urlRequest.setValue($1, forHTTPHeaderField: $0)
        }
        // Route cookie-opted-out requests through a jar-less session so the
        // shared cookies can't leak in regardless of httpShouldHandleCookies.
        let session = request.sendsCookies ? self.session : cookielessSession
        let task = session.dataTask(with: urlRequest) { data, response, error in
            if Self.isCancelled(error) {
                return
            }
            completion(Self.map(data: data, response: response, error: error))
        }
        cancellationToken?.register(task)
        task.resume()
    }
}
