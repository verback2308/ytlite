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
    private let liveBadgeView = UILabel()
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

        liveBadgeView.text = "● LIVE"
        liveBadgeView.textColor = .white
        liveBadgeView.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        liveBadgeView.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 0.9)
        liveBadgeView.layer.cornerRadius = 3
        liveBadgeView.layer.masksToBounds = true
        liveBadgeView.textAlignment = .center
        liveBadgeView.isHidden = true
        thumbnail.addSubview(liveBadgeView)

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

    /// Set to true to force grid layout (thumbnail on top, text below) regardless of cell width.
    var forceGridLayout: Bool = false {
        didSet { if oldValue != forceGridLayout { setNeedsLayout() } }
    }

    // MARK: - Manual layout (no Auto Layout — zero constraint solver overhead)

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        if !forceGridLayout && w > 350 {
            layoutHorizontal(w: w)
        } else {
            layoutGrid(w: w)
        }
    }

    private func layoutHorizontal(w: CGFloat) {
        let h = contentView.bounds.height
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12

        // Taller cell (≥150px, 1-column list mode) — matches SubscriptionVideoCell style
        if h >= 150 {
            let thumbH: CGFloat = h - vPad * 2
            let thumbW: CGFloat = (thumbH * 16.0 / 9.0).rounded()
            let clampedThumbW = min(thumbW, w * 0.55)
            let clampedThumbH = (clampedThumbW * 9.0 / 16.0).rounded()
            let thumbY = (h - clampedThumbH) / 2

            thumbnail.frame = CGRect(x: hPad, y: thumbY, width: clampedThumbW, height: clampedThumbH)

            if !durationLabel.isHidden {
                let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
                durationLabel.frame = CGRect(x: thumbnail.frame.maxX - dW - 4,
                                             y: thumbnail.frame.maxY - 22, width: dW, height: 18)
            }
            if !liveBadgeView.isHidden {
                let lW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
                liveBadgeView.frame = CGRect(x: thumbnail.frame.maxX - lW - 4,
                                             y: thumbnail.frame.maxY - 22, width: lW, height: 14)
            }

            let avatarSz: CGFloat = 32
            let textX = thumbnail.frame.maxX + hPad
            let textW = w - textX - hPad

            let titleH = titleLabel.sizeThatFits(CGSize(width: textW, height: 60)).height
            titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: min(titleH, 52))

            let afterTitle = titleLabel.frame.maxY + 8
            channelAvatarView.isHidden = false
            channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
            let labelX = textX + avatarSz + 8
            let labelW = w - labelX - hPad
            channelLabel.frame = CGRect(x: labelX, y: afterTitle + (avatarSz - 14) / 2, width: labelW, height: 14)
            metaLabel.frame = CGRect(x: textX, y: channelAvatarView.frame.maxY + 6, width: textW, height: 14)
            return
        }

        // Compact horizontal (narrow/multi-column sidebar mode)
        let thumbW: CGFloat = 160
        let thumbH: CGFloat = (thumbW * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            durationLabel.frame = CGRect(x: thumbnail.frame.maxX - dW - 4,
                                         y: thumbnail.frame.maxY - 22, width: dW, height: 18)
        }
        if !liveBadgeView.isHidden {
            let lW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
            liveBadgeView.frame = CGRect(x: thumbnail.frame.maxX - lW - 4,
                                         y: thumbnail.frame.maxY - 22, width: lW, height: 14)
        }

        channelAvatarView.isHidden = true
        let textX = thumbnail.frame.maxX + hPad
        let textW = w - textX - hPad
        let titleH = titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: min(titleH, 52))
        channelLabel.frame = CGRect(x: textX, y: titleLabel.frame.maxY + 4, width: textW, height: 14)
        metaLabel.frame = CGRect(x: textX, y: channelLabel.frame.maxY + 4, width: textW, height: 14)
    }

    private func layoutGrid(w: CGFloat) {
        let thumbH = (w * 9.0 / 16.0).rounded()

        thumbnail.frame = CGRect(x: 0, y: 0, width: w, height: thumbH)

        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            durationLabel.frame = CGRect(x: w - dW - 6, y: thumbH - 24, width: dW, height: 18)
        }

        if !liveBadgeView.isHidden {
            let lW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
            liveBadgeView.frame = CGRect(x: w - lW - 6, y: thumbH - 22, width: lW, height: 14)
        }

        let hp = VideoCell.hPad
        let avatarSz = channelAvatarView.isHidden ? 0 : VideoCell.avatarSize
        let avatarX: CGFloat = hp
        let textX = avatarSz > 0 ? avatarX + avatarSz + VideoCell.avatarGap : hp
        let textW = w - textX - hp

        if !channelAvatarView.isHidden {
            channelAvatarView.frame = CGRect(x: avatarX,
                                             y: thumbH + VideoCell.vPadAfterThumb,
                                             width: avatarSz, height: avatarSz)
        }

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

        if video.isLive {
            durationLabel.isHidden = true
            liveBadgeView.isHidden = false
        } else if let duration = video.duration, !duration.isEmpty {
            durationLabel.text = " \(duration) "
            durationLabel.isHidden = false
            liveBadgeView.isHidden = true
        } else {
            durationLabel.isHidden = true
            liveBadgeView.isHidden = true
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
        liveBadgeView.isHidden = true
        channelAvatarView.isHidden = false
        onChannelTap = nil
    }
}
