import Foundation

/// Fetches watch progress and fresh thumbnails from
/// YouTube history and syncs them into WatchProgressStore
/// and ThumbnailImageCache.
final class WatchProgressSyncService {
    static let shared = WatchProgressSyncService()

    private let client = InnertubeClient()
    private var isSyncing = false

    func syncIfNeeded() {
        let lastSync = UserDefaults.standard.double(
            forKey: "WatchProgressSync.lastSync"
        )
        let interval: TimeInterval = 6 * 60 * 60
        guard Date().timeIntervalSince1970 - lastSync
            > interval
        else {
            return
        }
        sync()
    }

    func sync() {
        guard !isSyncing,
              OAuthClient.shared.isSignedIn
        else {
            return
        }
        isSyncing = true
        client.fetchHistoryProgress { [weak self] result in
            let (progress, thumbs) = result
            self?.isSyncing = false
            guard !progress.isEmpty else {
                return
            }
            WatchProgressStore.shared
                .setServerFractions(progress)
            UserDefaults.standard.set(
                Date().timeIntervalSince1970,
                forKey: "WatchProgressSync.lastSync"
            )
            NotificationCenter.default.post(
                name: .watchProgressDidSync,
                object: nil,
                userInfo: [
                    "progress": progress,
                    "thumbnails": thumbs
                ]
            )
        }
    }
}

extension Notification.Name {
    static let watchProgressDidSync = Notification.Name(
        "watchProgressDidSync"
    )
}
