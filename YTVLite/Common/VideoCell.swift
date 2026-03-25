import UIKit

class VideoCell: UICollectionViewCell {

    static let reuseId = "VideoCell"

    // Manual layout constants
    private static let avatarSize: CGFloat = 32
    private static let hPad: CGFloat = 6
    private static let avatarGap: CGFloat = 10
    private static let vPadAfterThumb: CGFloat = 8

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = UILabel()
    private let channelAvatarView = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let metaLabel = UILabel()
    private var representedChannelId: String?
    var onChannelTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        thumbnail.layer.cornerRadius = 4
        thumbnail.layer.masksToBounds = true
        contentView.addSubview(thumbnail)

        durationLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        durationLabel.layer.cornerRadius = 3
        durationLabel.layer.masksToBounds = true
        durationLabel.textAlignment = .center
        thumbnail.addSubview(durationLabel)

        channelAvatarView.layer.cornerRadius = VideoCell.avatarSize / 2
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.isUserInteractionEnabled = true
        contentView.addSubview(channelAvatarView)

        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)

        channelLabel.font = UIFont.systemFont(ofSize: 11)
        channelLabel.isUserInteractionEnabled = true
        contentView.addSubview(channelLabel)

        metaLabel.font = UIFont.systemFont(ofSize: 11)
        contentView.addSubview(metaLabel)

        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelAvatarView.addGestureRecognizer(avatarTap)
        let labelTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelLabel.addGestureRecognizer(labelTap)

        applyTheme()
    }

    // MARK: - Manual layout (no Auto Layout — zero constraint solver overhead)

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let thumbH = (w * 9.0 / 16.0).rounded()

        // Thumbnail fills full width
        thumbnail.frame = CGRect(x: 0, y: 0, width: w, height: thumbH)

        // Duration badge — bottom-right of thumbnail
        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            durationLabel.frame = CGRect(x: w - dW - 6, y: thumbH - 24, width: dW, height: 18)
        }

        let hp = VideoCell.hPad
        let avatarSz = channelAvatarView.isHidden ? 0 : VideoCell.avatarSize
        let avatarX: CGFloat = hp
        let textX = avatarSz > 0 ? avatarX + avatarSz + VideoCell.avatarGap : hp
        let textW = w - textX - hp

        // Avatar — top-left of info area
        if !channelAvatarView.isHidden {
            channelAvatarView.frame = CGRect(x: avatarX,
                                             y: thumbH + VideoCell.vPadAfterThumb,
                                             width: avatarSz, height: avatarSz)
        }

        // Title — up to 2 lines, starts at same top as avatar
        let titleTop = thumbH + VideoCell.hPad
        let titleH = titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height
        titleLabel.frame = CGRect(x: textX, y: titleTop, width: textW, height: min(titleH, 52))

        let channelTop = titleLabel.frame.maxY + 2
        let channelH: CGFloat = 14
        channelLabel.frame = CGRect(x: textX, y: channelTop, width: textW, height: channelH)

        let metaTop = channelLabel.frame.maxY + 2
        metaLabel.frame = CGRect(x: textX, y: metaTop, width: textW, height: 14)
    }

    @objc private func handleChannelTap() { onChannelTap?() }

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        backgroundColor = t.surface
        titleLabel.textColor = t.primaryText
        channelLabel.textColor = t.secondaryText
        metaLabel.textColor = t.secondaryText
    }

    func configureSkeleton() {
        hideSkeleton()
        titleLabel.text = nil; channelLabel.text = nil; metaLabel.text = nil
        thumbnail.image = nil; channelAvatarView.image = nil
        durationLabel.isHidden = true
        contentView.showSkeleton()
    }

    func configure(with video: Video) {
        hideSkeleton()
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
            channelAvatarView.isHidden = false
            channelAvatarView.cancel()
            ChannelInfoStore.shared.fetch(channelId: channelId) { [weak self] result in
                guard let self = self, self.representedChannelId == channelId else { return }
                guard case .success(let info) = result,
                      let avatarURL = info.avatarURL,
                      let url = URL(string: avatarURL)
                else { return }
                self.channelAvatarView.setImage(url: url)
            }
        } else {
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
        metaLabel.text = nil
        durationLabel.text = nil
        durationLabel.isHidden = true
        channelAvatarView.isHidden = false
        onChannelTap = nil
    }
}
