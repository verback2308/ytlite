import UIKit

class ThumbnailImageView: UIImageView {

    private static let cache = NSCache<NSString, UIImage>()
    private var currentURL: URL?

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
            image = cached
            return
        }

        image = nil

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard
                let self = self,
                let data = data,
                let img = UIImage(data: data),
                self.currentURL == url
            else { return }

            ThumbnailImageView.cache.setObject(img, forKey: url.absoluteString as NSString)
            DispatchQueue.main.async { self.image = img }
        }.resume()
    }

    func cancel() {
        currentURL = nil
        image = nil
    }
}
