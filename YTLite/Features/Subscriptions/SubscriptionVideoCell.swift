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
    var onChannelTap: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        selectionStyle = .none

        thumbnail.layer.cornerRadius = 0
        thumbnail.layer.masksToBounds = true
        contentView.addSubview(thumbnail)

        durationLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = ThemeManager.shared.durationBackground
        durationLabel.layer.cornerRadius = 3
        durationLabel.layer.masksToBounds = true
        durationLabel.textAlignment = .center
        thumbnail.addSubview(durationLabel)

        channelAvatarView.layer.cornerRadius = 18
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.isUserInteractionEnabled = true
        contentView.addSubview(channelAvatarView)

        titleLabel.numberOfLines = 2
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(titleLabel)

        channelLabel.font = UIFont.systemFont(ofSize: 12)
        channelLabel.isUserInteractionEnabled = true
        contentView.addSubview(channelLabel)

        dateLabel.font = UIFont.systemFont(ofSize: 12)
        contentView.addSubview(dateLabel)

        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelAvatarView.addGestureRecognizer(avatarTap)
        let labelTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelLabel.addGestureRecognizer(labelTap)

        applyTheme()
    }

    // MARK: - Manual layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        if width > 500 {
            layoutHorizontal(width: width)
        } else {
            layoutVertical(width: width)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = size.width
        if width > 500 {
            return CGSize(width: width, height: 220)
        } else {
            let thumbH = (width * 9.0 / 16.0).rounded()
            let textW = width - 12 - 36 - 10 - 12
            let titleH = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height, 40)
            return CGSize(width: width, height: thumbH + 10 + titleH + 4 + 16 + 2 + 16 + 12)
        }
    }

    /// iPad / wide: thumbnail left, text right — matches original subscriptions style
    private func layoutHorizontal(width: CGFloat) {
        let height: CGFloat = 220
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbH: CGFloat = height - vPad * 2
        let thumbW: CGFloat = (thumbH * 16.0 / 9.0).rounded()

        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let dx = thumbnail.bounds.width - dW - 4
            let dy = thumbnail.bounds.height - 22
            durationLabel.frame = CGRect(x: dx, y: dy, width: dW, height: 18)
        }

        let avatarSz: CGFloat = 36
        let textX = thumbnail.frame.maxX + hPad
        let textW = width - textX - hPad

        let titleH = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height, 40)
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: titleH)

        let afterTitle = titleLabel.frame.maxY + 8
        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
        let labelX = textX + avatarSz + 10
        let labelW = width - labelX - hPad
        let chanY = afterTitle + (avatarSz - 15) / 2
        channelLabel.frame = CGRect(x: labelX, y: chanY, width: labelW, height: 15)
        let dateY = channelAvatarView.frame.maxY + 6
        dateLabel.frame = CGRect(x: textX, y: dateY, width: textW, height: 15)
    }

    /// iPhone / slide-over / narrow: thumbnail full-width on top, text below
    private func layoutVertical(width: CGFloat) {
        let thumbH = (width * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: 0, y: 0, width: width, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let dx = thumbnail.bounds.width - dW - 6
            let dy = thumbnail.bounds.height - 24
            durationLabel.frame = CGRect(x: dx, y: dy, width: dW, height: 18)
        }

        let avatarSz: CGFloat = 36
        let hPad: CGFloat = 12
        let avatarX: CGFloat = hPad
        let textX = avatarX + avatarSz + 10
        let textW = width - textX - hPad

        channelAvatarView.isHidden = false
        let avatarY = thumbH + 10
        channelAvatarView.frame = CGRect(x: avatarX, y: avatarY, width: avatarSz, height: avatarSz)

        let titleH = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height, 40)
        titleLabel.frame = CGRect(x: textX, y: thumbH + 10, width: textW, height: titleH)

        let channelTop = titleLabel.frame.maxY + 4
        channelLabel.frame = CGRect(x: textX, y: channelTop, width: textW, height: 16)
        dateLabel.frame = CGRect(x: textX, y: channelLabel.frame.maxY + 2, width: textW, height: 16)
    }

    @objc
    private func handleChannelTap() { onChannelTap?() }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        titleLabel.textColor = theme.primaryText
        channelLabel.textColor = theme.secondaryText
        dateLabel.textColor = theme.secondaryText
    }

    func configureSkeleton() {
        hideSkeleton()
        titleLabel.text = nil; channelLabel.text = nil; dateLabel.text = nil
        thumbnail.image = nil; channelAvatarView.image = nil
        durationLabel.isHidden = true
        contentView.showSkeleton()
    }

    func configure(with video: Video) {
        applyTheme()
        representedChannelId = video.channelId
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        dateLabel.text = VideoCardHelper.metaText(
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            separator: " · "
        )

        VideoCardHelper.loadChannelAvatar(for: video, into: channelAvatarView) { [weak self] in
            self?.representedChannelId == video.channelId
        }
        VideoCardHelper.configureBadges(
            video: video,
            durationLabel: durationLabel,
            liveBadgeView: nil
        )

        if let url = URL(string: video.thumbnailURL) {
            thumbnail.setImage(url: url)
        }
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hideSkeleton()
        representedChannelId = nil
        thumbnail.cancel()
        channelAvatarView.cancel()
        titleLabel.text = nil
        channelLabel.text = nil
        dateLabel.text = nil
        durationLabel.isHidden = true
        channelAvatarView.isHidden = false
        onChannelTap = nil
    }
}
