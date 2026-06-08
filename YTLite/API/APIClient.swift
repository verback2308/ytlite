import Foundation

class APIClient {
    @discardableResult
    func get(
        url: URL,
        headers: [String: String] = [:],
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) -> URLSessionDataTask {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.handleResponse(
                data: data,
                response: response,
                error: error,
                completion: completion
            )
        }
        cancellationToken?.register(task)
        task.resume()
        return task
    }

    @discardableResult
    func post(
        url: URL,
        body: Data,
        headers: [String: String] = [:],
        cancellationToken: CancellationToken? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) -> URLSessionDataTask {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            self.handleResponse(
                data: data,
                response: response,
                error: error,
                completion: completion
            )
        }
        cancellationToken?.register(task)
        task.resume()
        return task
    }

    private func handleResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        if isCancelled(error) {
            return
        }

        if let transportError = wrapTransportError(error) {
            completion(.failure(transportError))
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completion(.failure(APIError.invalidResponse))
            return
        }

        if let statusError = responseError(for: httpResponse.statusCode) {
            completion(.failure(statusError))
            return
        }

        guard let data else {
            completion(.failure(APIError.noData))
            return
        }

        completion(.success(data))
    }

    private func isCancelled(_ error: Error?) -> Bool {
        guard let error else {
            return false
        }
        return (error as NSError).code == NSURLErrorCancelled
    }

    private func wrapTransportError(_ error: Error?) -> APIError? {
        guard let error else {
            return nil
        }
        return .transport(error)
    }

    private func responseError(for statusCode: Int) -> APIError? {
        switch statusCode {
        case 200 ... 299:
            return nil
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 429:
            return .rateLimited
        case 500 ... 599:
            return .serverError(code: statusCode)
        default:
            return .invalidResponse
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
}
