import UIKit

class SubscriptionVideoCell: UITableViewCell {

    static let reuseId = "SubscriptionVideoCell"

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = UILabel()
    private let channelAvatarView = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let dateLabel = UILabel()
    private var representedChannelId: String?

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

        channelAvatarView.layer.cornerRadius = 18
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(channelAvatarView)

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
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            thumbnail.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            thumbnail.widthAnchor.constraint(equalTo: thumbnail.heightAnchor, multiplier: 16.0/9.0),

            durationLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -6),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -6),
            durationLabel.heightAnchor.constraint(equalToConstant: 18),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: thumbnail.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            channelAvatarView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            channelAvatarView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelAvatarView.widthAnchor.constraint(equalToConstant: 36),
            channelAvatarView.heightAnchor.constraint(equalToConstant: 36),

            channelLabel.centerYAnchor.constraint(equalTo: channelAvatarView.centerYAnchor),
            channelLabel.leadingAnchor.constraint(equalTo: channelAvatarView.trailingAnchor, constant: 10),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            dateLabel.topAnchor.constraint(equalTo: channelAvatarView.bottomAnchor, constant: 6),
            dateLabel.leadingAnchor.constraint(equalTo: channelAvatarView.leadingAnchor),
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
        representedChannelId = video.channelId
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        dateLabel.text = video.publishedAt.map(VideoFormatters.formatRelativeDate) ?? ""

        if let channelAvatarURL = video.channelAvatarURL, let url = URL(string: channelAvatarURL) {
            channelAvatarView.isHidden = false
            channelAvatarView.setImage(url: url)
        } else if let channelId = video.channelId {
            print("[SubscriptionVideoCell] resolving avatar for video \(video.id), channel \(channelId)")
            channelAvatarView.isHidden = false
            channelAvatarView.cancel()
            ChannelInfoStore.shared.fetch(channelId: channelId) { [weak self] result in
                guard let self = self, self.representedChannelId == channelId else { return }
                guard case .success(let info) = result,
                      let avatarURL = info.avatarURL,
                      let url = URL(string: avatarURL)
                else {
                    print("[SubscriptionVideoCell] avatar missing after fetch for channel \(channelId)")
                    return
                }
                self.channelAvatarView.setImage(url: url)
            }
        } else {
            print("[SubscriptionVideoCell] no channelId for video \(video.id)")
            channelAvatarView.isHidden = true
            channelAvatarView.cancel()
        }

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
        representedChannelId = nil
        thumbnail.cancel()
        channelAvatarView.cancel()
        titleLabel.text = nil
        channelLabel.text = nil
        dateLabel.text = nil
        durationLabel.isHidden = true
        channelAvatarView.isHidden = false
    }

}
