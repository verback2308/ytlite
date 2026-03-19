import Foundation

final class AppCache {
    static let shared = AppCache()

    private struct TimedWatchPage {
        let page: WatchPage
        let storedAt: Date
    }

    private var homeFeed: FeedPage?
    private var subscriptionsFeed: FeedPage?
    private var channelPages: [String: ChannelPage] = [:]
    private var watchPages: [String: TimedWatchPage] = [:]
    private let watchPageTTL: TimeInterval = 60 * 60

    private init() {}

    func cachedHomeFeed() -> FeedPage? {
        print("[AppCache] home \(homeFeed == nil ? "miss" : "hit")")
        return homeFeed
    }

    func setHomeFeed(_ page: FeedPage) {
        print("[AppCache] store home (\(page.videos.count) videos)")
        homeFeed = page
    }

    func clearHomeFeed() {
        print("[AppCache] clear home")
        homeFeed = nil
    }

    func cachedSubscriptionsFeed() -> FeedPage? {
        print("[AppCache] subscriptions \(subscriptionsFeed == nil ? "miss" : "hit")")
        return subscriptionsFeed
    }

    func setSubscriptionsFeed(_ page: FeedPage) {
        print("[AppCache] store subscriptions (\(page.videos.count) videos)")
        subscriptionsFeed = page
    }

    func clearSubscriptionsFeed() {
        print("[AppCache] clear subscriptions")
        subscriptionsFeed = nil
    }

    func cachedChannelPage(channelId: String) -> ChannelPage? {
        print("[AppCache] channel page \(channelPages[channelId] == nil ? "miss" : "hit") for \(channelId)")
        return channelPages[channelId]
    }

    func setChannelPage(_ page: ChannelPage, channelId: String) {
        print("[AppCache] store channel page for \(channelId) (\(page.videosPage.videos.count) videos)")
        channelPages[channelId] = page
    }

    func clearChannelPage(channelId: String) {
        print("[AppCache] clear channel page for \(channelId)")
        channelPages[channelId] = nil
    }

    func cachedWatchPage(videoId: String) -> WatchPage? {
        guard let entry = watchPages[videoId] else {
            print("[AppCache] watch page miss for \(videoId)")
            return nil
        }

        if Date().timeIntervalSince(entry.storedAt) > watchPageTTL {
            print("[AppCache] watch page expired for \(videoId)")
            watchPages[videoId] = nil
            return nil
        }

        print("[AppCache] watch page hit for \(videoId)")
        return entry.page
    }

    func setWatchPage(_ page: WatchPage, videoId: String) {
        print("[AppCache] store watch page for \(videoId) (\(page.relatedVideos.count) related)")
        watchPages[videoId] = TimedWatchPage(page: page, storedAt: Date())
    }

    func clearWatchPage(videoId: String) {
        print("[AppCache] clear watch page for \(videoId)")
        watchPages[videoId] = nil
    }
}
