import Foundation

/// Thin JSON-plane convenience over `HTTPTransport`. Kept as a narrow
/// data-oriented facade (`get`/`post` returning `Data`) that the Innertube
/// request executor builds on. All actual networking + status mapping lives in
/// the injected transport.
final class APIClient {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// JSON-plane status policy: any non-2xx becomes an `APIError`.
    private static func jsonData(
        from result: Result<HTTPResponse, Error>
    ) -> Result<Data, Error> {
        result.flatMap { response in
            if let error = APIError.from(status: response.status) {
                return .failure(error)
            }
            return .success(response.data)
        }
    }

    func get(
        url: URL,
        headers: [String: String] = [:],
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        transport.send(
            HTTPRequest(method: .get, url: url, headers: headers),
            cancellationToken: cancellationToken
        ) { result in
            completion(Self.jsonData(from: result))
        }
    }

    func post(
        url: URL,
        body: Data,
        headers: [String: String] = [:],
        cancellationToken: CancellationToken? = nil,
        sendsCookies: Bool = true,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        transport.send(
            HTTPRequest(
                method: .post,
                url: url,
                headers: headers,
                body: body,
                sendsCookies: sendsCookies
            ),
            cancellationToken: cancellationToken
        ) { result in
            completion(Self.jsonData(from: result))
        }
    }
}

enum APIError: Error {
    case noData
    case invalidURL
    case invalidResponse
    case decodingFailed
    case notReady
    case unauthorized
    case forbidden
    case rateLimited
    case serverError(code: Int)
    case transport(Error)

    /// Maps an HTTP status code to an error, or nil for 2xx.
    static func from(status: Int) -> APIError? {
        switch status {
        case 200 ... 299:
            return nil
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 429:
            return .rateLimited
        case 500 ... 599:
            return .serverError(code: status)
        default:
            return .invalidResponse
        }
    }
}
