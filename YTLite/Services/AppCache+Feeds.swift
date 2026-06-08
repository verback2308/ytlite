import Foundation

extension AppCache {
    func loadDiskValue<T: Codable>(
        _ type: T.Type,
        key: String,
        ttl: TimeInterval,
        completion: @escaping (T?) -> Void
    ) {
        guard AppCache.persistenceEnabled else {
            deliverOnMain(Optional<T>.none, completion: completion)
            return
        }
        diskQueue.async { [weak self] in
            guard let self else {
                return
            }
            let value = self.readDisk(type, key: key, ttl: ttl)
            self.deliverOnMain(value, completion: completion)
        }
    }

    // MARK: - Home
    func cachedHomeFeed() -> FeedPage? {
        homeFeed
    }

    func loadHomeFeed(completion: @escaping (FeedPage?) -> Void) {
        if let feed = homeFeed {
            AppLog.cache("home mem-hit videos=\(feed.videos.count)")
            deliverOnMain(feed, completion: completion)
            return
        }
        loadDiskValue(FeedPage.self, key: "home", ttl: feedTTL) { [weak self] feed in
            guard let self else {
                return
            }
            if let feed {
                self.homeFeed = feed
                AppLog.cache("home disk-hit videos=\(feed.videos.count)")
            } else {
                AppLog.cache("home miss")
            }
            completion(feed)
        }
    }

    func setHomeFeed(_ page: FeedPage) {
        homeFeed = page
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: "home")
        }
        AppLog.cache("home stored videos=\(page.videos.count)")
    }

    func clearHomeFeed() {
        homeFeed = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "home")
        }
    }

    // MARK: - Subscriptions
    func cachedSubscriptionsFeed() -> FeedPage? {
        subscriptionsFeed
    }

    func loadSubscriptionsFeed(completion: @escaping (FeedPage?) -> Void) {
        if let feed = subscriptionsFeed {
            AppLog.cache("subs mem-hit videos=\(feed.videos.count)")
            deliverOnMain(feed, completion: completion)
            return
        }
        loadDiskValue(FeedPage.self, key: "subscriptions", ttl: feedTTL) { [weak self] feed in
            guard let self else {
                return
            }
            if let feed {
                self.subscriptionsFeed = feed
                AppLog.cache("subs disk-hit videos=\(feed.videos.count)")
            } else {
                AppLog.cache("subs miss")
            }
            completion(feed)
        }
    }

    func setSubscriptionsFeed(_ page: FeedPage) {
        subscriptionsFeed = page
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: "subscriptions")
        }
        AppLog.cache("subs stored videos=\(page.videos.count)")
    }

    func clearSubscriptionsFeed() {
        subscriptionsFeed = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "subscriptions")
        }
    }

    // MARK: - History
    func cachedHistoryFeed() -> FeedPage? {
        historyFeed
    }

    func loadHistoryFeed(completion: @escaping (FeedPage?) -> Void) {
        if let feed = historyFeed {
            deliverOnMain(feed, completion: completion)
            return
        }
        loadDiskValue(FeedPage.self, key: "history", ttl: feedTTL) { [weak self] feed in
            guard let self else {
                return
            }
            if let feed {
                self.historyFeed = feed
            }
            completion(feed)
        }
    }

    func setHistoryFeed(_ page: FeedPage) {
        historyFeed = page
        diskQueue.async { [weak self] in
            self?.writeDisk(page, key: "history")
        }
    }

    func clearHistoryFeed() {
        historyFeed = nil
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "history")
        }
    }

    // MARK: - Clear All
    func clearAllDiskCache() {
        let channelInfoKeys = channelInfoMemory.keys
        homeFeed = nil
        subscriptionsFeed = nil
        historyFeed = nil
        channelInfoMemory.removeAll()
        diskQueue.async { [weak self] in
            self?.deleteDisk(key: "home")
            self?.deleteDisk(key: "subscriptions")
            self?.deleteDisk(key: "history")
            channelInfoKeys.forEach {
                self?.deleteDisk(key: "channel_info_\($0)")
            }
        }
    }
}
