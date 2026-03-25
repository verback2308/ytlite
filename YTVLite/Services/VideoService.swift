import Foundation

struct FeedPage: Codable {
    let videos: [Video]
    let continuation: String?
}

protocol VideoService {
    func fetchHomeFeed(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchSubscriptionFeed(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchHistory(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchPlaylists(completion: @escaping (Result<[Playlist], Error>) -> Void)
    func fetchNextPage(continuation: String, completion: @escaping (Result<FeedPage, Error>) -> Void)
    func search(query: String, completion: @escaping (Result<[Video], Error>) -> Void)
}
