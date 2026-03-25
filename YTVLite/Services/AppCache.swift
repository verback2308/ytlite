import Foundation

final class AppCache {
    static let shared = AppCache()
    private init() {}

    // MARK: - Settings
    static let persistenceKey = "feedCachePersistenceEnabled"
    static var persistenceEnabled: Bool {
        get { UserDefaults.standard.object(forKey: persistenceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: persistenceKey) }
    }
    private let feedTTL: TimeInterval = 24 * 60 * 60  // 24 hours

    // MARK: - Disk helpers

    private struct CacheEntry<T: Codable>: Codable {
        let data: T
        let storedAt: Date
    }

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeedCache", isDirectory: true)
    }

    private func ensureCacheDir() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func cacheURL(for key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).json")
    }

    private func readDisk<T: Codable>(_ type: T.Type, key: String, ttl: TimeInterval) -> T? {
        guard AppCache.persistenceEnabled else { return nil }
        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > ttl {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.data
    }

    private func writeDisk<T: Codable>(_ value: T, key: String) {
        guard AppCache.persistenceEnabled else { return }
        ensureCacheDir()
        let entry = CacheEntry(data: value, storedAt: Date())
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: cacheURL(for: key), options: .atomic)
        }
    }

    private func deleteDisk(key: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: key))
    }

    // MARK: - In-memory store

    private var homeFeed: FeedPage?
    private var subscriptionsFeed: FeedPage?
    private var historyFeed: FeedPage?

    // MARK: - Watch page cache (in-memory only, 1-hour TTL)
    private struct TimedWatchPage {
        let page: WatchPage
        let storedAt: Date
    }
    private var watchPages: [String: TimedWatchPage] = [:]
    private let watchPageTTL: TimeInterval = 60 * 60

    // MARK: - Home

    func cachedHomeFeed() -> FeedPage? {
        if let f = homeFeed { return f }
        if let f = readDisk(FeedPage.self, key: "home", ttl: feedTTL) {
            homeFeed = f
            return f
        }
        return nil
    }

    func setHomeFeed(_ page: FeedPage) {
        homeFeed = page
        writeDisk(page, key: "home")
    }

    func clearHomeFeed() {
        homeFeed = nil
        deleteDisk(key: "home")
    }

    // MARK: - Subscriptions

    func cachedSubscriptionsFeed() -> FeedPage? {
        if let f = subscriptionsFeed { return f }
        if let f = readDisk(FeedPage.self, key: "subscriptions", ttl: feedTTL) {
            subscriptionsFeed = f
            return f
        }
        return nil
    }

    func setSubscriptionsFeed(_ page: FeedPage) {
        subscriptionsFeed = page
        writeDisk(page, key: "subscriptions")
    }

    func clearSubscriptionsFeed() {
        subscriptionsFeed = nil
        deleteDisk(key: "subscriptions")
    }

    // MARK: - History

    func cachedHistoryFeed() -> FeedPage? {
        if let f = historyFeed { return f }
        if let f = readDisk(FeedPage.self, key: "history", ttl: feedTTL) {
            historyFeed = f
            return f
        }
        return nil
    }

    func setHistoryFeed(_ page: FeedPage) {
        historyFeed = page
        writeDisk(page, key: "history")
    }

    func clearHistoryFeed() {
        historyFeed = nil
        deleteDisk(key: "history")
    }

    // MARK: - Channel pages (in-memory only)
    private var channelPages: [String: ChannelPage] = [:]

    func cachedChannelPage(channelId: String) -> ChannelPage? { channelPages[channelId] }
    func setChannelPage(_ page: ChannelPage, channelId: String) { channelPages[channelId] = page }
    func clearChannelPage(channelId: String) { channelPages[channelId] = nil }

    // MARK: - Watch pages (in-memory only)

    func cachedWatchPage(videoId: String) -> WatchPage? {
        guard let entry = watchPages[videoId] else { return nil }
        if Date().timeIntervalSince(entry.storedAt) > watchPageTTL {
            watchPages[videoId] = nil
            return nil
        }
        return entry.page
    }

    func setWatchPage(_ page: WatchPage, videoId: String) {
        watchPages[videoId] = TimedWatchPage(page: page, storedAt: Date())
    }

    func clearWatchPage(videoId: String) { watchPages[videoId] = nil }

    // MARK: - Clear all feed disk cache

    func clearAllDiskCache() {
        deleteDisk(key: "home")
        deleteDisk(key: "subscriptions")
        deleteDisk(key: "history")
        homeFeed = nil
        subscriptionsFeed = nil
        historyFeed = nil
    }
}
