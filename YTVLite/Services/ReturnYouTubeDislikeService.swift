import Foundation

struct RYDVotes {
    let likes: Int
    let dislikes: Int
    let rating: Double
}

final class ReturnYouTubeDislikeService {
    static let shared = ReturnYouTubeDislikeService()
    private init() {}

    func fetchVotes(videoId: String, completion: @escaping (Result<RYDVotes, Error>) -> Void) {
        guard let url = URL(string: "https://returnyoutubedislikeapi.com/votes?videoId=\(videoId)") else {
            completion(.failure(NSError(domain: "RYD", code: 0)))
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let likes = json["likes"] as? Int,
                  let dislikes = json["dislikes"] as? Int,
                  let rating = json["rating"] as? Double
            else {
                completion(.failure(NSError(domain: "RYD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parse error"])))
                return
            }
            completion(.success(RYDVotes(likes: likes, dislikes: dislikes, rating: rating)))
        }.resume()
    }
}
