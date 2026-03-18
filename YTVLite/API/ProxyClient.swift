import Foundation

/// Wraps the yt-quality-helper proxy server API.
///
/// Flow:
/// 1. createSession(videoId:) → POST /api/session → returns sessionId + videoUrl
/// 2. Server downloads + merges the video in background
/// 3. GET /session/{id}/video.mp4 returns 202 while pending, mp4 when ready
class ProxyClient {

    private let api = APIClient()

    struct Session {
        let id: String
        let ready: Bool
        let videoURL: URL
    }

    /// Creates (or reuses) a server session for the given YouTube video ID.
    func createSession(videoId: String, completion: @escaping (Result<Session, Error>) -> Void) {
        guard let url = URL(string: "\(Config.proxyBaseURL)/api/session") else {
            completion(.failure(APIError.invalidURL)); return
        }
        let ytURL = "https://www.youtube.com/watch?v=\(videoId)"
        guard let body = try? JSONSerialization.data(withJSONObject: ["url": ytURL]) else {
            completion(.failure(APIError.decodingFailed)); return
        }
        let headers = ["Content-Type": "application/json"]
        api.post(url: url, headers: headers, body: body) { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let data):
                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let id = json["id"] as? String,
                    let videoURLString = json["videoUrl"] as? String,
                    let videoURL = URL(string: videoURLString)
                else {
                    completion(.failure(APIError.decodingFailed)); return
                }
                let ready = json["ready"] as? Bool ?? false
                completion(.success(Session(id: id, ready: ready, videoURL: videoURL)))
            }
        }
    }

    /// Polls the server until the video is ready (HTTP 200), then calls completion.
    /// Retries every `interval` seconds up to `maxAttempts` times.
    func waitUntilReady(session: Session, interval: TimeInterval = 2, maxAttempts: Int = 60,
                        completion: @escaping (Result<URL, Error>) -> Void) {
        if session.ready {
            completion(.success(session.videoURL)); return
        }
        poll(url: session.videoURL, attemptsLeft: maxAttempts, interval: interval, completion: completion)
    }

    private func poll(url: URL, attemptsLeft: Int, interval: TimeInterval,
                      completion: @escaping (Result<URL, Error>) -> Void) {
        if attemptsLeft <= 0 {
            completion(.failure(APIError.notReady)); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error { completion(.failure(error)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                completion(.success(url))
            } else {
                DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
                    self?.poll(url: url, attemptsLeft: attemptsLeft - 1, interval: interval, completion: completion)
                }
            }
        }.resume()
    }
}
