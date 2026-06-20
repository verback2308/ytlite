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
/// Updated by WatchtimeTracker on every ping
/// and by WatchProgressSyncService from server.
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private let key = "WatchProgressStore.v1"
    private let fractionKey = "WatchProgressStore.fractions"
    private let maxEntries = 200
    private let queue = DispatchQueue(
        label: "com.ytvlite.watch-progress",
        attributes: .concurrent
    )
    private var store: [String: [Double]] = [:]
    private var serverFractions: [String: Double] = [:]

    init() {
        load()
        loadFractions()
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

    func setFraction(
        videoId: String,
        fraction: Double
    ) {
        queue.async(flags: .barrier) {
            self.serverFractions[videoId] = fraction
            self.persistFractions()
        }
    }

    func setServerFractions(
        _ entries: [String: Double]
    ) {
        queue.async(flags: .barrier) {
            self.serverFractions = entries
            self.persistFractions()
        }
    }

    func progress(forVideoId videoId: String) -> WatchProgress? {
        let entry = queue.sync { store[videoId] }
        if let entry, entry.count == 2 {
            return WatchProgress(
                position: entry[0], duration: entry[1]
            )
        }
        if let frac = queue.sync(execute: {
            serverFractions[videoId]
        }) {
            return WatchProgress(
                position: frac, duration: 1.0
            )
        }
        return nil
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

    private func loadFractions() {
        guard let raw = UserDefaults.standard.dictionary(
            forKey: fractionKey
        ) as? [String: Double]
        else {
            return
        }
        serverFractions = raw
    }

    private func persistFractions() {
        UserDefaults.standard.set(
            serverFractions, forKey: fractionKey
        )
    }
}
