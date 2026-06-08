import UIKit

final class ChannelHeaderView: UIView {
    var bannerImageView = ThumbnailImageView(frame: .zero)
    var bannerOverlay = UIView()
    var avatarView = ThumbnailImageView(frame: .zero)
    var nameLabel = UILabel()
    var verifiedBadgeView = UIImageView()
    var subscribersLabel = UILabel()
    let subscribeButton = UIButton(type: .system)
    var separatorView = UIView()
    var nameSkeleton = SkeletonBlockView(cornerRadius: 6)
    var subsSkeleton = SkeletonBlockView(cornerRadius: 4)
    var btnSkeleton = SkeletonBlockView(cornerRadius: 18)
    var heightRef: NSLayoutConstraint?
    var avatarTopRef: NSLayoutConstraint?
    var nameTopRef: NSLayoutConstraint?
    let expandedHeight: CGFloat = 290
    let collapsedHeight: CGFloat = 0
    var bannerHeight: CGFloat = 120

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        configureBanner()
        configureLabels()
        configureButtonAndSeparator()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported")
    }

    func install(
        in parent: UIView,
        collectionView cv: UICollectionView,
        errorLabel: UILabel
    ) {
        parent.addSubview(self)
        parent.addSubview(errorLabel)
        addContentSubviews()
        configureCollectionView(cv)
        activateConstraints(parent, cv, errorLabel)
        showSkeletonState()
    }

    func update(with info: ChannelInfo, fallback: String) {
        hideSkeletonState()
        nameLabel.text = info.title.isEmpty ? fallback : info.title
        subscribersLabel.text = info.subscriberCountText
        verifiedBadgeView.isHidden = !info.isVerified
        loadImage(info.avatarURL, into: avatarView)
        loadImage(info.bannerURL, into: bannerImageView)
    }

    func updateSubscription(title: String, isEnabled: Bool) {
        subscribeButton.setTitle(title, for: .normal)
        subscribeButton.isEnabled = isEnabled
    }

    func applyTheme(isSubscribed: Bool) {
        let theme = ThemeManager.shared
        backgroundColor = theme.background
        nameLabel.textColor = theme.primaryText
        subscribersLabel.textColor = theme.secondaryText
        separatorView.backgroundColor = theme.separator
        applyButtonTheme(subscribed: isSubscribed, theme: theme)
    }

    func updateForScroll(_ scrollView: UIScrollView) {
        guard let heightRef, let avatarTopRef, let nameTopRef
        else {
            return
        }
        let inset = scrollView.adjustedContentInset.top
        let offset = scrollView.contentOffset.y + inset
        let range = expandedHeight - collapsedHeight
        let progress = min(max(offset / range, 0), 1)
        let ht = max(collapsedHeight, expandedHeight - offset)
        heightRef.constant = ht
        isHidden = ht <= 0
        scrollView.scrollIndicatorInsets.top = ht
        avatarTopRef.constant = (bannerHeight - 32) - 16 * progress
        nameTopRef.constant = 14 - 16 * progress
        applyScrollAlpha(progress)
        applyAvatarScale(progress)
    }

    func showSkeletonState() {
        bannerImageView.showSkeleton()
        avatarView.showSkeleton()
        setContentVisible(false)
    }

    func hideSkeletonState() {
        bannerImageView.hideSkeleton()
        avatarView.hideSkeleton()
        setContentVisible(true)
    }

    // MARK: - Private Setup

    private func configureBanner() {
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerImageView)
        bannerOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        bannerOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bannerOverlay)
        avatarView.layer.cornerRadius = 32
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureLabels() {
        nameLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        nameLabel.numberOfLines = 2
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            verifiedBadgeView.image = UIImage(
                systemName: "checkmark.seal.fill"
            )
        }
        verifiedBadgeView.tintColor = .systemBlue
        verifiedBadgeView.contentMode = .scaleAspectFit
        verifiedBadgeView.isHidden = true
        verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = false
        subscribersLabel.font = .systemFont(ofSize: 14)
        subscribersLabel.textAlignment = .center
        subscribersLabel.numberOfLines = 2
        subscribersLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureButtonAndSeparator() {
        subscribeButton.titleLabel?.font = .systemFont(
            ofSize: 15, weight: .semibold
        )
        subscribeButton.layer.cornerRadius = 18
        subscribeButton.contentEdgeInsets = UIEdgeInsets(
            top: 10, left: 18, bottom: 10, right: 18
        )
        subscribeButton.isEnabled = !OAuthClient.shared.isAnonymous
        subscribeButton.translatesAutoresizingMaskIntoConstraints = false
        separatorView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func addContentSubviews() {
        [
            avatarView, nameLabel, verifiedBadgeView,
            subscribersLabel, subscribeButton, separatorView,
            nameSkeleton, subsSkeleton, btnSkeleton
        ].forEach { addSubview($0) }
    }

    private func configureCollectionView(_ cv: UICollectionView) {
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.autoresizingMask = []
        cv.contentInset = UIEdgeInsets(
            top: expandedHeight, left: 0, bottom: 0, right: 0
        )
        cv.scrollIndicatorInsets = UIEdgeInsets(
            top: expandedHeight, left: 0, bottom: 0, right: 0
        )
        cv.setContentOffset(
            CGPoint(x: 0, y: -expandedHeight), animated: false
        )
    }

    // MARK: - Private Helpers

    private func applyScrollAlpha(_ progress: CGFloat) {
        avatarView.alpha = max(0, 1 - progress * 1.15)
        subscribersLabel.alpha = max(0, 1 - progress * 1.25)
        subscribeButton.alpha = max(0, 1 - progress * 1.35)
        separatorView.alpha = max(0, 1 - progress * 1.5)
        nameLabel.alpha = max(0, 1 - progress * 1.1)
        bannerImageView.alpha = max(0, 1 - progress * 2.0)
        bannerOverlay.alpha = bannerImageView.alpha
    }

    private func applyAvatarScale(_ progress: CGFloat) {
        let sc = 1 - (0.35 * progress)
        avatarView.transform = CGAffineTransform(
            scaleX: sc, y: sc
        )
    }

    private func applyButtonTheme(
        subscribed: Bool,
        theme: ThemeManager
    ) {
        if subscribed {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(
                theme.primaryText, for: .normal
            )
        } else {
            subscribeButton.backgroundColor = theme.accent
            subscribeButton.setTitleColor(.white, for: .normal)
        }
    }

    private func setContentVisible(_ visible: Bool) {
        nameLabel.isHidden = !visible
        subscribersLabel.isHidden = !visible
        subscribeButton.isHidden = !visible
        if !visible { verifiedBadgeView.isHidden = true }
        nameSkeleton.isHidden = visible
        subsSkeleton.isHidden = visible
        btnSkeleton.isHidden = visible
    }

    private func loadImage(
        _ urlString: String?,
        into imageView: ThumbnailImageView
    ) {
        guard let urlString, let url = URL(string: urlString)
        else {
            return
        }
        imageView.setImage(url: url)
    }
}
