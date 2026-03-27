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
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

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
        let w = contentView.bounds.width
        if w > 500 {
            layoutHorizontal(w: w)
        } else {
            layoutVertical(w: w)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let w = size.width
        if w > 500 {
            return CGSize(width: w, height: 220)
        } else {
            let thumbH = (w * 9.0 / 16.0).rounded()
            let textW = w - 12 - 36 - 10 - 12
            let titleH = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height, 40)
            return CGSize(width: w, height: thumbH + 10 + titleH + 4 + 16 + 2 + 16 + 12)
        }
    }

    /// iPad / wide: thumbnail left, text right — matches original subscriptions style
    private func layoutHorizontal(w: CGFloat) {
        let h: CGFloat = 220
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbH: CGFloat = h - vPad * 2
        let thumbW: CGFloat = (thumbH * 16.0 / 9.0).rounded()

        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            durationLabel.frame = CGRect(x: thumbnail.bounds.width - dW - 4,
                                         y: thumbnail.bounds.height - 22, width: dW, height: 18)
        }

        let avatarSz: CGFloat = 36
        let textX = thumbnail.frame.maxX + hPad
        let textW = w - textX - hPad

        let titleH = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height, 40)
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: titleH)

        let afterTitle = titleLabel.frame.maxY + 8
        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
        let labelX = textX + avatarSz + 10
        let labelW = w - labelX - hPad
        channelLabel.frame = CGRect(x: labelX, y: afterTitle + (avatarSz - 15) / 2, width: labelW, height: 15)
        dateLabel.frame = CGRect(x: textX, y: channelAvatarView.frame.maxY + 6, width: textW, height: 15)
    }

    /// iPhone / slide-over / narrow: thumbnail full-width on top, text below
    private func layoutVertical(w: CGFloat) {
        let thumbH = (w * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: 0, y: 0, width: w, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            durationLabel.frame = CGRect(x: thumbnail.bounds.width - dW - 6,
                                         y: thumbnail.bounds.height - 24, width: dW, height: 18)
        }

        let avatarSz: CGFloat = 36
        let hPad: CGFloat = 12
        let avatarX: CGFloat = hPad
        let textX = avatarX + avatarSz + 10
        let textW = w - textX - hPad

        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: avatarX, y: thumbH + 10, width: avatarSz, height: avatarSz)

        let titleH = min(titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height, 40)
        titleLabel.frame = CGRect(x: textX, y: thumbH + 10, width: textW, height: titleH)

        let channelTop = titleLabel.frame.maxY + 4
        channelLabel.frame = CGRect(x: textX, y: channelTop, width: textW, height: 16)
        dateLabel.frame = CGRect(x: textX, y: channelLabel.frame.maxY + 2, width: textW, height: 16)
    }

    @objc private func handleChannelTap() { onChannelTap?() }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        backgroundColor = t.background
        contentView.backgroundColor = t.background
        titleLabel.textColor = t.primaryText
        channelLabel.textColor = t.secondaryText
        dateLabel.textColor = t.secondaryText
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
        dateLabel.text = VideoCardHelper.metaText(viewCount: video.viewCount, publishedAt: video.publishedAt,
                                                  separator: " · ")

        VideoCardHelper.loadChannelAvatar(for: video, into: channelAvatarView) { [weak self] in
            self?.representedChannelId == video.channelId
        }
        VideoCardHelper.configureBadges(video: video, durationLabel: durationLabel, liveBadgeView: nil)

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
