import Foundation

// MARK: - Transport model

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

struct HTTPRequest {
    var method: HTTPMethod
    var url: URL
    var headers: [String: String]
    var body: Data?
    /// Per-request timeout; nil uses the session default.
    var timeout: TimeInterval?
    /// When false, the shared cookie storage is neither sent nor updated for
    /// this request — used to keep the anonymous MWEB playback flow from being
    /// contaminated by the app's authenticated (TV device) session cookies.
    var sendsCookies: Bool

    init(
        method: HTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        sendsCookies: Bool = true
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.sendsCookies = sendsCookies
    }
}

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let data: Data
}

/// The single abstraction over the HTTP transport. All networking flows through
/// a `HTTPTransport` so cross-cutting concerns (auth, logging, retry) compose as
/// decorators and the only `URLSession` user is `URLSessionTransport`.
///
/// Failures are reported as `APIError` (the app-wide error type). Cancellation
/// is honoured via `CancellationToken`; a cancelled request never calls back.
protocol HTTPTransport: AnyObject {
    func send(
        _ request: HTTPRequest,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    )
}
