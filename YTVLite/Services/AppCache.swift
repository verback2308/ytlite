import Foundation

final class AppCache {
    static let shared = AppCache()
    private init() {}

    // MARK: - Settings
    static var persistenceEnabled: Bool {
        get { UserDefaults.standard.object(forKey: UserDefaultsKeys.Cache.feedPersistenceEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.Cache.feedPersistenceEnabled) }
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
        let t0 = Date()
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(entry.storedAt)
        if age > ttl {
            AppLog.cache("disk expired key=\(key) age=\(Int(age))s")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        AppLog.cache("disk-read key=\(key) age=\(Int(age))s read=\(ms)ms size=\(data.count)b")
        return entry.data
    }

    private func writeDisk<T: Codable>(_ value: T, key: String) {
        guard AppCache.persistenceEnabled else { return }
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
        if let f = homeFeed {
            AppLog.cache("home mem-hit videos=\(f.videos.count)")
            return f
        }
        if let f = readDisk(FeedPage.self, key: "home", ttl: feedTTL) {
            homeFeed = f
            AppLog.cache("home disk-hit videos=\(f.videos.count)")
            return f
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
        if let f = subscriptionsFeed {
            AppLog.cache("subs mem-hit videos=\(f.videos.count)")
            return f
        }
        if let f = readDisk(FeedPage.self, key: "subscriptions", ttl: feedTTL) {
            subscriptionsFeed = f
            AppLog.cache("subs disk-hit videos=\(f.videos.count)")
            return f
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

    // MARK: - Channel info (disk-persistent, static header metadata)
    private let channelInfoTTL: TimeInterval = 24 * 60 * 60
    private var channelInfoMemory: [String: ChannelInfo] = [:]

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
        AppLog.cache("channel-info stored: \(channelId) title='\(info.title)' banner=\(info.bannerURL != nil ? "YES" : "NO")")
    }

    func clearChannelInfo(channelId: String) {
        channelInfoMemory[channelId] = nil
        deleteDisk(key: "channel_info_\(channelId)")
    }

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
        // Clear all channel info disk entries
        channelInfoMemory.keys.forEach { deleteDisk(key: "channel_info_\($0)") }
        channelInfoMemory.removeAll()
    }
}
