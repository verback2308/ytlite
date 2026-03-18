import UIKit

class SubscriptionVideoCell: UITableViewCell {

    static let reuseId = "SubscriptionVideoCell"

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = UILabel()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let dateLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        selectionStyle = .none

        thumbnail.layer.cornerRadius = 4
        thumbnail.layer.masksToBounds = true
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnail)

        durationLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        durationLabel.layer.cornerRadius = 3
        durationLabel.layer.masksToBounds = true
        durationLabel.textAlignment = .center
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.addSubview(durationLabel)

        titleLabel.numberOfLines = 2
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        channelLabel.font = UIFont.systemFont(ofSize: 12)
        channelLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(channelLabel)

        dateLabel.font = UIFont.systemFont(ofSize: 12)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 200),
            thumbnail.heightAnchor.constraint(equalToConstant: 112),
            thumbnail.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),
            thumbnail.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            durationLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -6),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -6),
            durationLabel.heightAnchor.constraint(equalToConstant: 18),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: thumbnail.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            dateLabel.topAnchor.constraint(equalTo: channelLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        applyTheme()
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        backgroundColor = t.background
        contentView.backgroundColor = t.background
        titleLabel.textColor = t.primaryText
        channelLabel.textColor = t.secondaryText
        dateLabel.textColor = t.secondaryText
    }

    func configure(with video: Video) {
        applyTheme()
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        dateLabel.text = video.publishedAt.flatMap { Self.formatDate($0) } ?? ""

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
        dateLabel.text = nil
        durationLabel.isHidden = true
    }

    private static func formatDate(_ iso: String) -> String? {
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        guard let date = parser.date(from: iso) else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
