import Foundation

final class AppCache {
    // MARK: - Subtypes
    private struct CacheEntry<T: Codable>: Codable {
        let data: T
        let storedAt: Date
    }

    private struct TimedWatchPage {
        let page: WatchPage
        let storedAt: Date
    }

    // MARK: - Type Properties
    static let shared = AppCache()

    static var persistenceEnabled: Bool {
        get {
            let key = UserDefaultsKeys.Cache.feedPersistenceEnabled
            return UserDefaults.standard.object(forKey: key) as? Bool ?? true
        }
        set {
            let key = UserDefaultsKeys.Cache.feedPersistenceEnabled
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    // MARK: - Instance Properties
    private let feedTTL: TimeInterval = 24 * 60 * 60
    private let watchPageTTL: TimeInterval = 60 * 60
    private let channelInfoTTL: TimeInterval = 24 * 60 * 60
    private var homeFeed: FeedPage?
    private var subscriptionsFeed: FeedPage?
    private var historyFeed: FeedPage?
    private var watchPages: [String: TimedWatchPage] = [:]
    private var channelPages: [String: ChannelPage] = [:]
    private var channelInfoMemory: [String: ChannelInfo] = [:]

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeedCache", isDirectory: true)
    }

    // MARK: - Initializer
    private init() {}

    // MARK: - Disk Helpers
    private func ensureCacheDir() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func cacheURL(for key: String) -> URL {
        cacheDir.appendingPathComponent("\(key).json")
    }

    private func readDisk<T: Codable>(_ type: T.Type, key: String, ttl: TimeInterval) -> T? {
        guard AppCache.persistenceEnabled else {
            return nil
        }
        let url = cacheURL(for: key)
        let t0 = Date()
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else {
            return nil
        }
        let age = Date().timeIntervalSince(entry.storedAt)
        if age > ttl {
            AppLog.cache("disk expired key=\(key) age=\(Int(age))s")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1_000)
        AppLog.cache("disk-read key=\(key) age=\(Int(age))s read=\(ms)ms size=\(data.count)b")
        return entry.data
    }

    private func writeDisk<T: Codable>(_ value: T, key: String) {
        guard AppCache.persistenceEnabled else {
            return
        }
        ensureCacheDir()
        let entry = CacheEntry(data: value, storedAt: Date())
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: cacheURL(for: key), options: .atomic)
            AppLog.cache("disk-write key=\(key) size=\(data.count)b")
        }
    }

    private func deleteDisk(key: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: key))
    }

    // MARK: - Home
    func cachedHomeFeed() -> FeedPage? {
        if let feed = homeFeed {
            AppLog.cache("home mem-hit videos=\(feed.videos.count)")
            return feed
        }
        if let feed = readDisk(FeedPage.self, key: "home", ttl: feedTTL) {
            homeFeed = feed
            AppLog.cache("home disk-hit videos=\(feed.videos.count)")
            return feed
        }
        AppLog.cache("home miss")
        return nil
    }

    func setHomeFeed(_ page: FeedPage) {
        homeFeed = page
        writeDisk(page, key: "home")
        AppLog.cache("home stored videos=\(page.videos.count)")
    }

    func clearHomeFeed() {
        homeFeed = nil
        deleteDisk(key: "home")
    }

    // MARK: - Subscriptions
    func cachedSubscriptionsFeed() -> FeedPage? {
        if let feed = subscriptionsFeed {
            AppLog.cache("subs mem-hit videos=\(feed.videos.count)")
            return feed
        }
        if let feed = readDisk(FeedPage.self, key: "subscriptions", ttl: feedTTL) {
            subscriptionsFeed = feed
            AppLog.cache("subs disk-hit videos=\(feed.videos.count)")
            return feed
        }
        AppLog.cache("subs miss")
        return nil
    }

    func setSubscriptionsFeed(_ page: FeedPage) {
        subscriptionsFeed = page
        writeDisk(page, key: "subscriptions")
        AppLog.cache("subs stored videos=\(page.videos.count)")
    }

    func clearSubscriptionsFeed() {
        subscriptionsFeed = nil
        deleteDisk(key: "subscriptions")
    }

    // MARK: - History
    func cachedHistoryFeed() -> FeedPage? {
        if let feed = historyFeed {
            return feed
        }
        if let feed = readDisk(FeedPage.self, key: "history", ttl: feedTTL) {
            historyFeed = feed
            return feed
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

    // MARK: - Channel Pages
    func cachedChannelPage(channelId: String) -> ChannelPage? {
        channelPages[channelId]
    }

    func setChannelPage(_ page: ChannelPage, channelId: String) {
        channelPages[channelId] = page
    }

    func clearChannelPage(channelId: String) {
        channelPages[channelId] = nil
    }

    // MARK: - Channel Info
    func cachedChannelInfo(channelId: String) -> ChannelInfo? {
        if let info = channelInfoMemory[channelId] {
            AppLog.cache("channel-info mem-hit: \(channelId)")
            return info
        }
        let key = "channel_info_\(channelId)"
        if let info = readDisk(ChannelInfo.self, key: key, ttl: channelInfoTTL) {
            channelInfoMemory[channelId] = info
            AppLog.cache("channel-info disk-hit: \(channelId) title='\(info.title)'")
            return info
        }
        AppLog.cache("channel-info miss: \(channelId)")
        return nil
    }

    func setChannelInfo(_ info: ChannelInfo, channelId: String) {
        channelInfoMemory[channelId] = info
        writeDisk(info, key: "channel_info_\(channelId)")
        let hasBanner = info.bannerURL != nil ? "YES" : "NO"
        AppLog.cache("channel-info stored: \(channelId) title='\(info.title)' banner=\(hasBanner)")
    }

    func clearChannelInfo(channelId: String) {
        channelInfoMemory[channelId] = nil
        deleteDisk(key: "channel_info_\(channelId)")
    }

    // MARK: - Watch Pages
    func cachedWatchPage(videoId: String) -> WatchPage? {
        guard let entry = watchPages[videoId] else {
            return nil
        }
        if Date().timeIntervalSince(entry.storedAt) > watchPageTTL {
            watchPages[videoId] = nil
            return nil
        }
        return entry.page
    }

    func setWatchPage(_ page: WatchPage, videoId: String) {
        watchPages[videoId] = TimedWatchPage(page: page, storedAt: Date())
    }

    func clearWatchPage(videoId: String) {
        watchPages[videoId] = nil
    }

    // MARK: - Clear All
    func clearAllDiskCache() {
        deleteDisk(key: "home")
        deleteDisk(key: "subscriptions")
        deleteDisk(key: "history")
        homeFeed = nil
        subscriptionsFeed = nil
        historyFeed = nil
        channelInfoMemory.keys.forEach { deleteDisk(key: "channel_info_\($0)") }
        channelInfoMemory.removeAll()
    }
}
