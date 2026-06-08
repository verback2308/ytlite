// swiftlint:disable file_length
import UIKit

class VideoCell: UICollectionViewCell {
    static let reuseId = "VideoCell"

    private static let avatarSize: CGFloat = 32
    private static let hPad: CGFloat = 6
    private static let avatarGap: CGFloat = 10
    private static let vPadAfterThumb: CGFloat = 8

    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let durationLabel = UILabel()
    private let liveBadgeView = UILabel()
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private var watchFraction: CGFloat = 0
    private let channelAvatarView = ThumbnailImageView(frame: .zero)
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let metaLabel = UILabel()
    private var representedChannelId: String?
    var onChannelTap: (() -> Void)?

    /// Force grid layout regardless of cell width.
    var forceGridLayout: Bool = false {
        didSet {
            if oldValue != forceGridLayout { setNeedsLayout() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
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

    override func layoutSubviews() {
        super.layoutSubviews()
        let cellWidth = contentView.bounds.width
        if !forceGridLayout && cellWidth > 350 {
            layoutHorizontal(cellWidth: cellWidth)
        } else {
            layoutGrid(cellWidth: cellWidth)
        }
        layoutProgress()
    }

    private func layoutProgress() {
        let barH: CGFloat = 3
        let thumbW = thumbnail.bounds.width
        let thumbH = thumbnail.bounds.height
        guard thumbW > 0, thumbH > 0 else {
            return
        }
        let barY = thumbH - barH
        progressTrack.frame = CGRect(x: 0, y: barY, width: thumbW, height: barH)
        progressFill.frame = CGRect(x: 0, y: barY, width: thumbW * watchFraction, height: barH)
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
        watchFraction = 0
        progressTrack.isHidden = true
        progressFill.isHidden = true
        onChannelTap = nil
    }
}

// MARK: - Setup

extension VideoCell {
    private func setupUI() {
        thumbnail.layer.cornerRadius = 4
        thumbnail.layer.masksToBounds = true
        contentView.addSubview(thumbnail)

        progressTrack.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        progressTrack.isHidden = true
        thumbnail.addSubview(progressTrack)
        progressFill.backgroundColor = UIColor(
            red: 1, green: 0, blue: 0, alpha: 1
        )
        thumbnail.addSubview(progressFill)

        durationLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.backgroundColor = ThemeManager.shared.durationBackground
        durationLabel.layer.cornerRadius = 3
        durationLabel.layer.masksToBounds = true
        durationLabel.textAlignment = .center
        thumbnail.addSubview(durationLabel)

        liveBadgeView.text = "● LIVE"
        liveBadgeView.textColor = .white
        liveBadgeView.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        liveBadgeView.backgroundColor = ThemeManager.shared.liveBadgeBackground
        liveBadgeView.layer.cornerRadius = 3
        liveBadgeView.layer.masksToBounds = true
        liveBadgeView.textAlignment = .center
        liveBadgeView.isHidden = true
        thumbnail.addSubview(liveBadgeView)

        setupInfoArea()
        applyTheme()
    }

    private func setupInfoArea() {
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
    }
}

// MARK: - Layout

extension VideoCell {
    private func layoutHorizontal(cellWidth: CGFloat) {
        let cellHeight = contentView.bounds.height
        if cellHeight >= 150 {
            layoutHorizontalTall(cellWidth: cellWidth, cellHeight: cellHeight)
        } else {
            layoutHorizontalCompact(cellWidth: cellWidth)
        }
    }

    private func layoutHorizontalTall(cellWidth: CGFloat, cellHeight: CGFloat) {
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbH = cellHeight - vPad * 2
        let thumbW = (thumbH * 16.0 / 9.0).rounded()
        let clampedW = min(thumbW, cellWidth * 0.55)
        let clampedH = (clampedW * 9.0 / 16.0).rounded()
        let thumbY = (cellHeight - clampedH) / 2
        thumbnail.frame = CGRect(x: hPad, y: thumbY, width: clampedW, height: clampedH)
        layoutBadgesForHorizontal()
        let avatarSz: CGFloat = 32
        let textX = thumbnail.frame.maxX + hPad
        let textW = cellWidth - textX - hPad
        let titleH = titleLabel.sizeThatFits(CGSize(width: textW, height: 60)).height
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: min(titleH, 52))
        let afterTitle = titleLabel.frame.maxY + 8
        channelAvatarView.isHidden = false
        channelAvatarView.frame = CGRect(x: textX, y: afterTitle, width: avatarSz, height: avatarSz)
        let labelX = textX + avatarSz + 8
        let labelW = cellWidth - labelX - hPad
        let channelY = afterTitle + (avatarSz - 14) / 2
        channelLabel.frame = CGRect(x: labelX, y: channelY, width: labelW, height: 14)
        let metaY = channelAvatarView.frame.maxY + 6
        metaLabel.frame = CGRect(x: textX, y: metaY, width: textW, height: 14)
    }

    private func layoutBadgesForHorizontal() {
        if !durationLabel.isHidden {
            let badgeW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let badgeX = thumbnail.frame.maxX - badgeW - 4
            let badgeY = thumbnail.frame.maxY - 22
            durationLabel.frame = CGRect(x: badgeX, y: badgeY, width: badgeW, height: 18)
        }
        if !liveBadgeView.isHidden {
            let badgeW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
            let badgeX = thumbnail.frame.maxX - badgeW - 4
            let badgeY = thumbnail.frame.maxY - 22
            liveBadgeView.frame = CGRect(x: badgeX, y: badgeY, width: badgeW, height: 14)
        }
    }

    private func layoutHorizontalCompact(cellWidth: CGFloat) {
        let vPad: CGFloat = 10
        let hPad: CGFloat = 12
        let thumbW: CGFloat = 160
        let thumbH = (thumbW * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: hPad, y: vPad, width: thumbW, height: thumbH)
        layoutBadgesForHorizontal()
        channelAvatarView.isHidden = true
        let textX = thumbnail.frame.maxX + hPad
        let textW = cellWidth - textX - hPad
        let titleH = titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height
        titleLabel.frame = CGRect(x: textX, y: vPad, width: textW, height: min(titleH, 52))
        let channelY = titleLabel.frame.maxY + 4
        channelLabel.frame = CGRect(x: textX, y: channelY, width: textW, height: 14)
        let metaY = channelLabel.frame.maxY + 4
        metaLabel.frame = CGRect(x: textX, y: metaY, width: textW, height: 14)
    }

    private func layoutGrid(cellWidth: CGFloat) {
        let thumbH = (cellWidth * 9.0 / 16.0).rounded()
        thumbnail.frame = CGRect(x: 0, y: 0, width: cellWidth, height: thumbH)
        if !durationLabel.isHidden {
            let dW = max(36, durationLabel.intrinsicContentSize.width + 8)
            let dx = cellWidth - dW - 6
            durationLabel.frame = CGRect(x: dx, y: thumbH - 24, width: dW, height: 18)
        }
        if !liveBadgeView.isHidden {
            let lW = max(40, liveBadgeView.intrinsicContentSize.width + 8)
            let lx = cellWidth - lW - 6
            liveBadgeView.frame = CGRect(x: lx, y: thumbH - 22, width: lW, height: 14)
        }
        let hp = VideoCell.hPad
        let avatarSz: CGFloat = channelAvatarView.isHidden ? 0 : VideoCell.avatarSize
        let avatarX: CGFloat = hp
        let textX = avatarSz > 0 ? avatarX + avatarSz + VideoCell.avatarGap : hp
        let textW = cellWidth - textX - hp
        let avatarY = thumbH + VideoCell.vPadAfterThumb
        if !channelAvatarView.isHidden {
            let sz = avatarSz
            channelAvatarView.frame = CGRect(x: avatarX, y: avatarY, width: sz, height: sz)
        }
        let titleTop = thumbH + VideoCell.hPad
        let titleH = titleLabel.sizeThatFits(CGSize(width: textW, height: 52)).height
        titleLabel.frame = CGRect(x: textX, y: titleTop, width: textW, height: min(titleH, 52))
        let channelTop = titleLabel.frame.maxY + 2
        channelLabel.frame = CGRect(x: textX, y: channelTop, width: textW, height: 14)
        let metaTop = channelLabel.frame.maxY + 2
        metaLabel.frame = CGRect(x: textX, y: metaTop, width: textW, height: 14)
    }
}

// MARK: - Actions & Theming

extension VideoCell {
    @objc
    private func handleChannelTap() {
        onChannelTap?()
    }

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        backgroundColor = theme.surface
        titleLabel.textColor = theme.primaryText
        channelLabel.textColor = theme.secondaryText
        metaLabel.textColor = theme.secondaryText
    }
}

// MARK: - Configuration

extension VideoCell {
    func configureSkeleton() {
        hideSkeleton()
        titleLabel.text = nil
        channelLabel.text = nil
        metaLabel.text = nil
        thumbnail.image = nil
        channelAvatarView.image = nil
        durationLabel.isHidden = true
        contentView.showSkeleton()
    }

    func configure(with video: Video) {
        hideSkeleton()
        representedChannelId = video.channelId
        titleLabel.text = video.title
        channelLabel.text = video.channelName
        metaLabel.text = VideoCardHelper.metaText(
            viewCount: video.viewCount,
            publishedAt: video.publishedAt
        )
        VideoCardHelper.loadChannelAvatar(
            for: video,
            into: channelAvatarView
        ) { [weak self] in
            self?.representedChannelId == video.channelId
        }
        VideoCardHelper.configureBadges(
            video: video,
            durationLabel: durationLabel,
            liveBadgeView: liveBadgeView
        )
        if let url = URL(string: video.thumbnailURL) {
            thumbnail.setImage(url: url)
        }
        applyWatchProgress(videoId: video.id)
        setNeedsLayout()
    }

    private func applyWatchProgress(videoId: String) {
        if let prog = WatchProgressStore.shared.progress(
            forVideoId: videoId
        ), prog.shouldShow {
            watchFraction = CGFloat(prog.fraction)
            progressTrack.isHidden = false
            progressFill.isHidden = false
        } else {
            watchFraction = 0
            progressTrack.isHidden = true
            progressFill.isHidden = true
        }
    }
}
