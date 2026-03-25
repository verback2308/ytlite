import Foundation

class APIClient {

    @discardableResult
    func get(url: URL, headers: [String: String] = [:],
             cancellationToken: CancellationToken? = nil,
             completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                completion(.failure(error)); return
            }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            completion(.success(data))
        }
        cancellationToken?.register(task)
        task.resume()
        return task
    }

    @discardableResult
    func post(url: URL, headers: [String: String] = [:], body: Data,
              cancellationToken: CancellationToken? = nil,
              completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                completion(.failure(error)); return
            }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            completion(.success(data))
        }
        cancellationToken?.register(task)
        task.resume()
        return task
    }
}

enum APIError: Error {
    case noData
    case invalidURL
    case decodingFailed
    case notReady
    case unauthorized
}
