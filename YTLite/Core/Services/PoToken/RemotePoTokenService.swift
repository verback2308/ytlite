import Foundation

/// Mints a GVS proof-of-origin (`pot`) token bound to a content id.
protocol PoTokenProvider: AnyObject {
    /// - Parameter identifier: the content binding. For the mweb client this is
    ///   the VIDEO ID (YouTube's current experiment binds the pot to the video,
    ///   not visitorData).
    func fetchSessionToken(
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    )
}

/// Fetches the `pot` from a remote bgutil-ytdlp-pot-provider over HTTP. Replaces
/// the on-device WKWebView BotGuard mint, whose tokens GVS rejected even when
/// correctly video-id-bound (the reference BgUtils tokens were accepted).
final class RemotePoTokenService: PoTokenProvider {
    enum ProviderError: Error {
        case notConfigured
        case badResponse
    }

    static let shared = RemotePoTokenService()

    private let transport: HTTPTransport
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    init(transport: HTTPTransport = ServiceContainer.transport) {
        self.transport = transport
    }

    func fetchSessionToken(
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        if let cached = cachedToken(for: identifier) {
            AppLog.poToken("cache hit for \(identifier)")
            completion(.success(cached))
            return
        }
        guard let endpoint = AppURLs.PoTokenProvider.endpoint,
              let body = try? JSONSerialization.data(
                  withJSONObject: ["content_binding": identifier]
              ) else {
            completion(.failure(ProviderError.notConfigured))
            return
        }
        let request = HTTPRequest(
            method: .post,
            url: endpoint,
            headers: [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON],
            body: body,
            timeout: 15
        )
        AppLog.poToken("requesting pot for \(identifier) via \(endpoint.host ?? "")")
        transport.send(request, cancellationToken: nil) { [weak self] result in
            self?.handle(result: result, identifier: identifier, completion: completion)
        }
    }

    private func handle(
        result: Result<HTTPResponse, Error>,
        identifier: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        switch result {
        case .failure(let error):
            AppLog.poToken("pot request failed: \(error.localizedDescription)")
            completion(.failure(error))
        case .success(let response):
            guard let token = parseToken(response.data), !token.isEmpty else {
                AppLog.poToken("pot response missing poToken (status \(response.status))")
                completion(.failure(ProviderError.badResponse))
                return
            }
            AppLog.poToken(
                "got pot for \(identifier) len=\(token.count) tail=\(token.suffix(4))"
            )
            storeToken(token, for: identifier)
            completion(.success(token))
        }
    }

    private func parseToken(_ data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["poToken"] ?? json?["po_token"]) as? String
    }

    private func cachedToken(for identifier: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[identifier]
    }

    private func storeToken(_ token: String, for identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[identifier] = token
    }
}
