import Foundation

struct FeedPage {
    let videos: [Video]
    let continuation: String?
}

protocol VideoService {
    func fetchHomeFeed(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchSubscriptionFeed(completion: @escaping (Result<FeedPage, Error>) -> Void)
    func fetchNextPage(continuation: String, completion: @escaping (Result<FeedPage, Error>) -> Void)
    func search(query: String, completion: @escaping (Result<[Video], Error>) -> Void)
}
