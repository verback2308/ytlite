import Foundation

class APIClient {

    func get(url: URL, headers: [String: String] = [:],
             completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            completion(.success(data))
        }.resume()
    }

    func post(url: URL, headers: [String: String] = [:], body: Data,
              completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(APIError.noData)); return }
            completion(.success(data))
        }.resume()
    }
}

enum APIError: Error {
    case noData
    case invalidURL
    case decodingFailed
    case notReady
    case unauthorized
}
