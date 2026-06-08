import UIKit

class ThumbnailImageView: UIImageView {
    private static let cache = ImageMemoryCache()
    private static let diskCache = ImageDiskCache()
    private var currentURL: URL?
    private var task: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = ThemeManager.shared.thumbnailPlaceholder
        contentMode = .scaleAspectFill
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func clearCache() {
        AppLog.img("clear all")
        cache.removeAll()
        diskCache.clear()
    }

    func setImage(url: URL) {
        if currentURL == url, image != nil || task != nil {
            return
        }
        task?.cancel()
        task = nil
        currentURL = url
        loadFromMemoryOrDisk(url: url)
    }

    private func loadFromMemoryOrDisk(url: URL) {
        let key = url.absoluteString
        if let cached = ThumbnailImageView.cache.object(forKey: key) {
            AppLog.img("mem-hit \(url.lastPathComponent)")
            image = cached
            task = nil
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, self.currentURL == url else {
                return
            }
            self.loadFromDiskOrNetwork(url: url, cacheKey: key)
        }
    }

    private func loadFromDiskOrNetwork(url: URL, cacheKey: String) {
        if let cached = ThumbnailImageView.diskCache.image(for: url) {
            AppLog.img("disk-hit \(url.lastPathComponent)")
            ThumbnailImageView.cache.setObject(cached, forKey: cacheKey, cost: cached.memoryCost)
            DispatchQueue.main.async { [weak self] in
                guard self?.currentURL == url else {
                    return
                }
                self?.task = nil
                self?.image = cached
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard self?.currentURL == url else {
                return
            }
            self?.image = nil
        }

        fetchFromNetwork(url: url, cacheKey: cacheKey)
    }

    private func fetchFromNetwork(url: URL, cacheKey: String) {
        AppLog.img("fetch \(url.lastPathComponent)")
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            defer {
                DispatchQueue.main.async { [weak self] in
                    guard self?.currentURL == url else {
                        return
                    }
                    self?.task = nil
                }
            }
            guard let self,
                  let data,
                  let img = UIImage(data: data),
                  self.currentURL == url else {
                return
            }
            ThumbnailImageView.cache.setObject(img, forKey: cacheKey, cost: img.memoryCost)
            ThumbnailImageView.diskCache.store(data: data, for: url)
            AppLog.img("stored \(url.lastPathComponent)")
            DispatchQueue.main.async { [weak self] in
                guard self?.currentURL == url else {
                    return
                }
                self?.image = img
            }
        }
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        currentURL = nil
        image = nil
    }
}

/// Type-safe wrapper around NSCache to avoid legacy_objc_type.
private final class ImageMemoryCache {
    // swiftlint:disable:next legacy_objc_type
    private let backing = NSCache<NSString, UIImage>()

    init() {
        backing.countLimit = 300
        backing.totalCostLimit = 64 * 1_024 * 1_024
    }

    func object(forKey key: String) -> UIImage? {
        backing.object(forKey: key as NSString) // swiftlint:disable:this legacy_objc_type
    }

    func setObject(_ image: UIImage, forKey key: String, cost: Int) {
        backing.setObject(
            image,
            forKey: key as NSString, // swiftlint:disable:this legacy_objc_type
            cost: cost
        )
    }

    func removeAll() {
        backing.removeAllObjects()
    }
}

private final class ImageDiskCache {
    private let fm = FileManager.default
    private let cacheDir: URL
    private let ttl: TimeInterval = 60 * 60 * 24 * 7

    init() {
        let caches = fm.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDir = caches.appendingPathComponent(
            "ImageDiskCache",
            isDirectory: true
        )
        try? fm.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func image(for url: URL) -> UIImage? {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: url))
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date
        else { return nil }

        if Date().timeIntervalSince(modifiedAt) > ttl {
            AppLog.img("disk expired \(url.absoluteString)")
            try? fm.removeItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: data)
    }

    func store(data: Data, for url: URL) {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: url))
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? fm.removeItem(at: cacheDir)
        try? fm.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func cacheKey(for url: URL) -> String {
        "\(fnv1a64Hex(for: url.absoluteString)).img"
    }

    private func fnv1a64Hex(for string: String) -> String {
        let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01b3
        let hash = string.utf8.reduce(offsetBasis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(format: "%016llx", hash)
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}
