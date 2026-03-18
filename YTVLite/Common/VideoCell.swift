import UIKit

class VideoCell: UICollectionViewCell {

    static let reuseId = "VideoCell"

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let viewCountLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = .black

        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnail)

        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        channelLabel.textColor = UIColor(white: 0.6, alpha: 1)
        channelLabel.font = UIFont.systemFont(ofSize: 12)
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(channelLabel)

        viewCountLabel.textColor = UIColor(white: 0.6, alpha: 1)
        viewCountLabel.font = UIFont.systemFont(ofSize: 12)
        viewCountLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(viewCountLabel)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0/16.0),

            titleLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            viewCountLabel.topAnchor.constraint(equalTo: channelLabel.bottomAnchor, constant: 2),
            viewCountLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            viewCountLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    func configure(with video: Video) {
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        viewCountLabel.text = video.viewCount ?? ""
        if let url = URL(string: video.thumbnailURL) {
            thumbnail.setImage(url: url)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.cancel()
        titleLabel.text = nil
        channelLabel.text = nil
        viewCountLabel.text = nil
    }
}
