import UIKit

class ThumbnailImageView: UIImageView {

    private static let cache = NSCache<NSString, UIImage>()
    private static let diskCache = ImageDiskCache()
    private var currentURL: URL?

    static func clearCache() {
        cache.removeAllObjects()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.15, alpha: 1)
        contentMode = .scaleAspectFill
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setImage(url: URL) {
        currentURL = url

        if let cached = ThumbnailImageView.cache.object(forKey: url.absoluteString as NSString) {
            print("[ImageCache] memory hit \(url.absoluteString)")
            image = cached
            return
        }

        if let cached = ThumbnailImageView.diskCache.image(for: url) {
            print("[ImageCache] disk hit \(url.absoluteString)")
            ThumbnailImageView.cache.setObject(cached, forKey: url.absoluteString as NSString)
            image = cached
            return
        }

        print("[ImageCache] network fetch \(url.absoluteString)")
        image = nil

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let self = self,
                let data = data,
                let img = UIImage(data: data),
                self.currentURL == url
            else { return }

            ThumbnailImageView.cache.setObject(img, forKey: url.absoluteString as NSString)
            ThumbnailImageView.diskCache.store(data: data, for: url)
            DispatchQueue.main.async { self.image = img }
        }.resume()
    }

    func cancel() {
        currentURL = nil
        image = nil
    }
}

private final class ImageDiskCache {
    private let fm = FileManager.default
    private let cacheDir: URL
    private let ttl: TimeInterval = 60 * 60 * 24 * 7

    init() {
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDir = caches.appendingPathComponent("ImageDiskCache", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
    }

    func image(for url: URL) -> UIImage? {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: url))
        guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date
        else { return nil }

        if Date().timeIntervalSince(modifiedAt) > ttl {
            print("[ImageCache] disk expired \(url.absoluteString)")
            try? fm.removeItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }

    func store(data: Data, for url: URL) {
        let fileURL = cacheDir.appendingPathComponent(cacheKey(for: url))
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cacheKey(for url: URL) -> String {
        let allowed = CharacterSet.alphanumerics
        let compact = url.absoluteString.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let truncated = String(String(compact).prefix(180))
        return truncated + ".img"
    }
}
