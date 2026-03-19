import UIKit

class VideoCell: UICollectionViewCell {

    static let reuseId = "VideoCell"

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = UILabel()
    private let channelAvatarView = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let metaLabel = UILabel()
    private var representedChannelId: String?
    private var avatarWidthConstraint: NSLayoutConstraint!
    private var avatarMaxWidthConstraint: NSLayoutConstraint!
    private var avatarHeightConstraint: NSLayoutConstraint!
    private var titleLeadingConstraint: NSLayoutConstraint!
    var onChannelTap: (() -> Void)?

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

        channelAvatarView.layer.cornerRadius = 16
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.translatesAutoresizingMaskIntoConstraints = false
        channelAvatarView.isUserInteractionEnabled = true
        contentView.addSubview(channelAvatarView)

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
        channelLabel.isUserInteractionEnabled = true
        contentView.addSubview(channelLabel)

        // Meta (views • date)
        metaLabel.textColor = ThemeManager.shared.secondaryText
        metaLabel.font = UIFont.systemFont(ofSize: 11)
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(metaLabel)

        avatarWidthConstraint = channelAvatarView.widthAnchor.constraint(equalToConstant: 32)
        avatarWidthConstraint.priority = .defaultHigh
        avatarMaxWidthConstraint = channelAvatarView.widthAnchor.constraint(lessThanOrEqualToConstant: 32)
        avatarHeightConstraint = channelAvatarView.heightAnchor.constraint(equalTo: channelAvatarView.widthAnchor)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: channelAvatarView.trailingAnchor, constant: 10)
        titleLeadingConstraint.priority = .defaultHigh
        channelAvatarView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        channelAvatarView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        channelLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: contentView.topAnchor),
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            thumbnail.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            thumbnail.heightAnchor.constraint(equalTo: thumbnail.widthAnchor, multiplier: 9.0/16.0),

            durationLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: -6),
            durationLabel.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -6),
            durationLabel.heightAnchor.constraint(equalToConstant: 18),
            durationLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            channelAvatarView.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 8),
            channelAvatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            avatarWidthConstraint,
            avatarMaxWidthConstraint,
            avatarHeightConstraint,

            titleLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 6),
            titleLeadingConstraint,
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),

            channelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            channelLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            channelLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: channelLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])

        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelAvatarView.addGestureRecognizer(avatarTap)

        let labelTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelLabel.addGestureRecognizer(labelTap)
    }

    @objc private func handleChannelTap() {
        onChannelTap?()
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
        representedChannelId = video.channelId
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        let views = video.viewCount ?? ""
        let date = video.publishedAt.map(VideoFormatters.formatRelativeDate) ?? ""
        metaLabel.text = [views, date].filter { !$0.isEmpty }.joined(separator: " • ")

        if let channelAvatarURL = video.channelAvatarURL, let url = URL(string: channelAvatarURL) {
            channelAvatarView.isHidden = false
            channelAvatarView.setImage(url: url)
        } else if let channelId = video.channelId {
            print("[VideoCell] resolving avatar for video \(video.id), channel \(channelId)")
            channelAvatarView.isHidden = false
            channelAvatarView.cancel()
            ChannelInfoStore.shared.fetch(channelId: channelId) { [weak self] result in
                guard let self = self, self.representedChannelId == channelId else { return }
                guard case .success(let info) = result,
                      let avatarURL = info.avatarURL,
                      let url = URL(string: avatarURL)
                else {
                    print("[VideoCell] avatar unavailable for channel \(channelId)")
                    return
                }
                self.channelAvatarView.setImage(url: url)
            }
        } else {
            print("[VideoCell] no channelId for video \(video.id) (\(video.channelName))")
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
        metaLabel.text = nil
        durationLabel.text = nil
        durationLabel.isHidden = true
        channelAvatarView.isHidden = false
        onChannelTap = nil
    }
}
