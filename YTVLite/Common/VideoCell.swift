import UIKit

class VideoCell: UICollectionViewCell {

    static let reuseId = "VideoCell"

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = UILabel()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let metaLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        // Thumbnail
        thumbnail.layer.cornerRadius = 4
        thumbnail.layer.masksToBounds = true
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnail)

        // Duration overlay
        durationLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        durationLabel.layer.cornerRadius = 3
        durationLabel.layer.masksToBounds = true
        durationLabel.textAlignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.addSubview(durationLabel)

        // Title
        titleLabel.textColor = ThemeManager.shared.primaryText
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Channel
        channelLabel.textColor = ThemeManager.shared.secondaryText
        channelLabel.font = UIFont.systemFont(ofSize: 11)
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(channelLabel)

        // Meta (views • date)
        metaLabel.textColor = ThemeManager.shared.secondaryText
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0/16.0),

            durationLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -6),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -6),
            durationLabel.heightAnchor.constraint(equalToConstant: 18),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: channelLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        backgroundColor = t.surface
        titleLabel.textColor = t.primaryText
        channelLabel.textColor = t.secondaryText
        metaLabel.textColor = t.secondaryText
    }

    func configure(with video: Video) {
        applyTheme()
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        let views = video.viewCount ?? ""
        let date = video.publishedAt.map(VideoFormatters.formatRelativeDate) ?? ""
        metaLabel.text = [views, date].filter { !$0.isEmpty }.joined(separator: " • ")

        if let duration = video.duration, !duration.isEmpty {
            durationLabel.text = " \(duration) "
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        if let url = URL(string: video.thumbnailURL) {
            thumbnail.setImage(url: url)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.cancel()
        titleLabel.text = nil
        channelLabel.text = nil
        metaLabel.text = nil
        durationLabel.text = nil
        durationLabel.isHidden = true
        metaLabel.text = nil
    }
}
