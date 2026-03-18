import Foundation

final class AppCache {
    static let shared = AppCache()

    private var homeFeed: FeedPage?
    private var subscriptionsFeed: FeedPage?
    private var channelPages: [String: ChannelPage] = [:]

    private init() {}

    func cachedHomeFeed() -> FeedPage? {
        homeFeed
    }

    func setHomeFeed(_ page: FeedPage) {
        homeFeed = page
    }

    func clearHomeFeed() {
        homeFeed = nil
    }

    func cachedSubscriptionsFeed() -> FeedPage? {
        subscriptionsFeed
    }

    func setSubscriptionsFeed(_ page: FeedPage) {
        subscriptionsFeed = page
    }

    func clearSubscriptionsFeed() {
        subscriptionsFeed = nil
    }

    func cachedChannelPage(channelId: String) -> ChannelPage? {
        channelPages[channelId]
    }

    func setChannelPage(_ page: ChannelPage, channelId: String) {
        channelPages[channelId] = page
    }

    func clearChannelPage(channelId: String) {
        channelPages[channelId] = nil
    }
}
