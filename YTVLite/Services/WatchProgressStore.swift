import Foundation

struct WatchProgress {
    let position: TimeInterval
    let duration: TimeInterval

    var fraction: Double {
        guard duration > 0 else {
            return 0
        }
        return min(1.0, position / duration)
    }

    var shouldShow: Bool {
        fraction > 0.03 && fraction < 0.97
    }
}

/// Persists per-video watch progress locally.
/// Updated by WatchtimeTracker on every ping.
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private let key = "WatchProgressStore.v1"
    private let maxEntries = 200
    private let queue = DispatchQueue(
        label: "com.ytvlite.watch-progress",
        attributes: .concurrent
    )
    private var store: [String: [Double]] = [:]

    init() {
        load()
    }

    func setProgress(
        videoId: String,
        position: TimeInterval,
        duration: TimeInterval
    ) {
        queue.async(flags: .barrier) {
            self.store[videoId] = [position, duration]
            if self.store.count > self.maxEntries {
                let excess = self.store.count - self.maxEntries
                self.store.keys
                    .prefix(excess)
                    .forEach { self.store.removeValue(forKey: $0) }
            }
            self.persist()
        }
    }

    func progress(forVideoId videoId: String) -> WatchProgress? {
        let entry = queue.sync { store[videoId] }
        guard let entry,
              entry.count == 2
        else {
            return nil
        }
        return WatchProgress(position: entry[0], duration: entry[1])
    }

    // MARK: - Persistence

    private func load() {
        guard let raw = UserDefaults.standard.dictionary(
            forKey: key
        ) as? [String: [Double]]
        else {
            return
        }
        store = raw
    }

    private func persist() {
        UserDefaults.standard.set(store, forKey: key)
    }
}
