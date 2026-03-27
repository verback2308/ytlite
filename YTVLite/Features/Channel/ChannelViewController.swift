import UIKit

final class ChannelViewController: VideosViewController {

    private let client: VideoService = ServiceContainer.video
    private let cache = AppCache.shared
    private let channelId: String
    private let initialChannelName: String

    private let headerView = UIView()
    private let bannerImageView = ThumbnailImageView(frame: .zero)
    private let bannerOverlay = UIView()
    private let avatarView = ThumbnailImageView(frame: .zero)
    private let nameLabel = UILabel()
    private let verifiedBadgeView = UIImageView()
    private let subscribersLabel = UILabel()
    private let subscribeButton = UIButton(type: .system)
    private let separatorView = UIView()
    private let errorLabel = UILabel()

    // Skeleton placeholders shown while loading
    private let nameSkeletonView = SkeletonBlockView(cornerRadius: 6)
    private let subsSkeletonView = SkeletonBlockView(cornerRadius: 4)
    private let buttonSkeletonView = SkeletonBlockView(cornerRadius: 18)

    private var headerHeightConstraint: NSLayoutConstraint!
    private var avatarTopConstraint: NSLayoutConstraint!
    private var nameTopConstraint: NSLayoutConstraint!
    private var isSubscribed: Bool = false
    private var currentChannelPage: ChannelPage?

    private lazy var infoBarButton: UIBarButtonItem = {
        if #available(iOS 13, *) {
            return UIBarButtonItem(image: UIImage(systemName: "info.circle"),
                                   style: .plain, target: self, action: #selector(showAbout))
        } else {
            return UIBarButtonItem(title: "ℹ️", style: .plain, target: self, action: #selector(showAbout))
        }
    }()

    private let expandedHeaderHeight: CGFloat = 290
    private let collapsedHeaderHeight: CGFloat = 0
    private let bannerHeight: CGFloat = 120

    override var columns: Int {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return 1
        }
        let w = view.bounds.width
        if w < 500 { return 1 }
        return w > view.bounds.height ? 3 : 2
    }

    init(channelId: String, channelName: String) {
        self.channelId = channelId
        self.initialChannelName = channelName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialChannelName
        setupHeader()
        applyHeaderTheme()

        // Instant header from disk cache (survives restarts)
        if let cachedInfo = cache.cachedChannelInfo(channelId: channelId) {
            applyChannelInfo(cachedInfo)
        }
        // In-memory full page (videos list, same session)
        if let cachedPage = cache.cachedChannelPage(channelId: channelId) {
            spinner.stopAnimating()
            applyChannelPage(cachedPage)
        }
        // Always refresh for live subscribe state + latest videos
        loadChannel()
    }

    override func applyTheme() {
        super.applyTheme()
        applyHeaderTheme()
    }

    override func handleRefresh() {
        cache.clearChannelPage(channelId: channelId)
        loadChannel()
    }

    override func handleLoadMore() {
        guard let continuation = currentContinuation else {
            finishLoadingMore()
            return
        }

        client.fetchNextPage(continuation: continuation) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let page):
                    self?.appendPage(page)
                case .failure(let error):
                    print("[ChannelViewController] pagination failed \(self?.channelId ?? "nil"): \(error)")
                    self?.finishLoadingMore()
                }
            }
        }
    }

    override func handleScroll(_ scrollView: UIScrollView) {
        guard headerHeightConstraint != nil,
              avatarTopConstraint != nil,
              nameTopConstraint != nil
        else { return }

        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let progress = min(max(offset / (expandedHeaderHeight - collapsedHeaderHeight), 0), 1)
        let height = max(collapsedHeaderHeight, expandedHeaderHeight - offset)

        headerHeightConstraint.constant = height
        headerView.isHidden = height <= 0
        collectionView.scrollIndicatorInsets.top = height
        avatarTopConstraint.constant = (bannerHeight - 32) - (16 * progress)
        nameTopConstraint.constant = 14 - (16 * progress)

        let expandedAlpha = 1 - progress * 1.15
        avatarView.alpha = max(0, expandedAlpha)
        subscribersLabel.alpha = max(0, 1 - progress * 1.25)
        subscribeButton.alpha = max(0, 1 - progress * 1.35)
        separatorView.alpha = max(0, 1 - progress * 1.5)
        nameLabel.alpha = max(0, 1 - progress * 1.1)
        // Banner fades out early so it doesn't abruptly clip
        bannerImageView.alpha = max(0, 1 - progress * 2.0)
        bannerOverlay.alpha = bannerImageView.alpha

        let avatarScale = 1 - (0.35 * progress)
        avatarView.transform = CGAffineTransform(scaleX: avatarScale, y: avatarScale)
    }

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.clipsToBounds = true
        bannerImageView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(bannerImageView)

        bannerOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        bannerOverlay.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(bannerOverlay)

        avatarView.layer.cornerRadius = 32
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        nameLabel.numberOfLines = 2
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        if #available(iOS 13.0, *) {
            verifiedBadgeView.image = UIImage(systemName: "checkmark.seal.fill")
        }
        verifiedBadgeView.tintColor = .systemBlue
        verifiedBadgeView.contentMode = .scaleAspectFit
        verifiedBadgeView.isHidden = true
        verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = false

        subscribersLabel.font = UIFont.systemFont(ofSize: 14)
        subscribersLabel.textAlignment = .center
        subscribersLabel.numberOfLines = 2
        subscribersLabel.translatesAutoresizingMaskIntoConstraints = false

        subscribeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        subscribeButton.layer.cornerRadius = 18
        subscribeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        subscribeButton.isEnabled = !OAuthClient.shared.isAnonymous
        subscribeButton.addTarget(self, action: #selector(subscribeButtonTapped), for: .touchUpInside)
        subscribeButton.translatesAutoresizingMaskIntoConstraints = false

        separatorView.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.text = "Channel unavailable"
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.font = UIFont.systemFont(ofSize: 15)
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.isHidden = true

        [avatarView, nameLabel, verifiedBadgeView, subscribersLabel, subscribeButton, separatorView, errorLabel,
         nameSkeletonView, subsSkeletonView, buttonSkeletonView].forEach {
            headerView.addSubview($0)
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.autoresizingMask = []
        collectionView.contentInset = UIEdgeInsets(top: expandedHeaderHeight, left: 0, bottom: 0, right: 0)
        collectionView.scrollIndicatorInsets = UIEdgeInsets(top: expandedHeaderHeight, left: 0, bottom: 0, right: 0)

        headerHeightConstraint = headerView.heightAnchor.constraint(equalToConstant: expandedHeaderHeight)
        avatarTopConstraint = avatarView.topAnchor.constraint(equalTo: headerView.topAnchor, constant: bannerHeight - 32)
        nameTopConstraint = nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerHeightConstraint,

            bannerImageView.topAnchor.constraint(equalTo: headerView.topAnchor),
            bannerImageView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            bannerImageView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            bannerImageView.heightAnchor.constraint(equalToConstant: bannerHeight),

            bannerOverlay.topAnchor.constraint(equalTo: bannerImageView.topAnchor),
            bannerOverlay.leadingAnchor.constraint(equalTo: bannerImageView.leadingAnchor),
            bannerOverlay.trailingAnchor.constraint(equalTo: bannerImageView.trailingAnchor),
            bannerOverlay.bottomAnchor.constraint(equalTo: bannerImageView.bottomAnchor),

            avatarTopConstraint,
            avatarView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 64),
            avatarView.heightAnchor.constraint(equalToConstant: 64),

            nameTopConstraint,
            nameLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -44),

            verifiedBadgeView.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            verifiedBadgeView.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            verifiedBadgeView.widthAnchor.constraint(equalToConstant: 16),
            verifiedBadgeView.heightAnchor.constraint(equalToConstant: 16),

            subscribersLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            subscribersLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            subscribersLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),

            subscribeButton.topAnchor.constraint(equalTo: subscribersLabel.bottomAnchor, constant: 14),
            subscribeButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            subscribeButton.heightAnchor.constraint(equalToConstant: 36),

            separatorView.topAnchor.constraint(equalTo: subscribeButton.bottomAnchor, constant: 18),
            separatorView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1),
            separatorView.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),

            // Skeleton placeholders — same positions as real views
            nameSkeletonView.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
            nameSkeletonView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            nameSkeletonView.widthAnchor.constraint(equalToConstant: 160),
            nameSkeletonView.heightAnchor.constraint(equalToConstant: 20),

            subsSkeletonView.topAnchor.constraint(equalTo: nameSkeletonView.bottomAnchor, constant: 10),
            subsSkeletonView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            subsSkeletonView.widthAnchor.constraint(equalToConstant: 110),
            subsSkeletonView.heightAnchor.constraint(equalToConstant: 14),

            buttonSkeletonView.topAnchor.constraint(equalTo: subsSkeletonView.bottomAnchor, constant: 14),
            buttonSkeletonView.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            buttonSkeletonView.widthAnchor.constraint(equalToConstant: 120),
            buttonSkeletonView.heightAnchor.constraint(equalToConstant: 36),

            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])

        collectionView.setContentOffset(CGPoint(x: 0, y: -expandedHeaderHeight), animated: false)
        showHeaderSkeleton()
    }

    private func showHeaderSkeleton() {
        bannerImageView.showSkeleton()
        avatarView.showSkeleton()
        nameLabel.isHidden = true
        subscribersLabel.isHidden = true
        subscribeButton.isHidden = true
        verifiedBadgeView.isHidden = true
        nameSkeletonView.isHidden = false
        subsSkeletonView.isHidden = false
        buttonSkeletonView.isHidden = false
    }

    private func hideHeaderSkeleton() {
        bannerImageView.hideSkeleton()
        avatarView.hideSkeleton()
        nameLabel.isHidden = false
        subscribersLabel.isHidden = false
        subscribeButton.isHidden = false
        nameSkeletonView.isHidden = true
        subsSkeletonView.isHidden = true
        buttonSkeletonView.isHidden = true
    }

    private func applyHeaderTheme() {
        let theme = ThemeManager.shared
        headerView.backgroundColor = theme.background
        nameLabel.textColor = theme.primaryText
        subscribersLabel.textColor = theme.secondaryText
        separatorView.backgroundColor = theme.separator
        errorLabel.textColor = theme.secondaryText

        if subscribeButton.currentTitle == "Subscribed" {
            subscribeButton.backgroundColor = theme.surface
            subscribeButton.setTitleColor(theme.primaryText, for: .normal)
        } else {
            subscribeButton.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
            subscribeButton.setTitleColor(.white, for: .normal)
        }
    }

    private func loadChannel() {
        errorLabel.isHidden = true
        client.fetchChannelPage(channelId: channelId) { [weak self] result in
            DispatchQueue.main.async {
                self?.spinner.stopAnimating()
                self?.endRefreshing()

                switch result {
                case .success(let page):
                    self?.applyChannelPage(page)
                case .failure(let error):
                    print("[ChannelViewController] load failed \(self?.channelId ?? "nil"): \(error)")
                    self?.finishLoadingMore()
                    self?.errorLabel.isHidden = false
                }
            }
        }
    }

    /// Apply only the static header metadata (from disk cache on launch).
    private func applyChannelInfo(_ info: ChannelInfo) {
        hideHeaderSkeleton()
        title = info.title.isEmpty ? initialChannelName : info.title
        nameLabel.text = info.title.isEmpty ? initialChannelName : info.title
        subscribersLabel.text = info.subscriberCountText
        verifiedBadgeView.isHidden = !info.isVerified
        if let avatarURL = info.avatarURL, let url = URL(string: avatarURL) {
            avatarView.setImage(url: url)
        }
        if let bannerURLStr = info.bannerURL, let url = URL(string: bannerURLStr) {
            bannerImageView.setImage(url: url)
        }
        let hasAbout = info.description != nil || info.contactInfo != nil || info.videoCountText != nil
        navigationItem.rightBarButtonItem = hasAbout ? infoBarButton : nil
    }

    private func applyChannelPage(_ page: ChannelPage) {
        hideHeaderSkeleton()
        currentChannelPage = page
        title = page.info.title.isEmpty ? initialChannelName : page.info.title
        nameLabel.text = page.info.title.isEmpty ? initialChannelName : page.info.title
        subscribersLabel.text = page.info.subscriberCountText
        subscribeButton.setTitle(page.subscribeButtonText ?? (page.isSubscribed ? "Subscribed" : "Subscribe"), for: .normal)
        isSubscribed = page.isSubscribed
        applyHeaderTheme()

        let hasAbout = page.info.description != nil || page.info.contactInfo != nil || page.info.videoCountText != nil
        navigationItem.rightBarButtonItem = hasAbout ? infoBarButton : nil

        if let avatarURL = page.info.avatarURL, let url = URL(string: avatarURL) {
            avatarView.setImage(url: url)
        }

        if let bannerURLStr = page.info.bannerURL, let url = URL(string: bannerURLStr) {
            bannerImageView.setImage(url: url)
        }

        verifiedBadgeView.isHidden = !page.info.isVerified

        let pageWithChannelAvatars = ChannelPage(info: page.info,
                                                 videosPage: FeedPage(videos: page.videosPage.videos.map {
            Video(id: $0.id,
                  title: $0.title,
                  channelId: $0.channelId,
                  channelName: $0.channelName,
                  channelAvatarURL: $0.channelAvatarURL ?? page.info.avatarURL,
                  thumbnailURL: $0.thumbnailURL,
                  viewCount: $0.viewCount,
                  publishedAt: $0.publishedAt,
                  duration: $0.duration,
                  isLive: $0.isLive)
        }, continuation: page.videosPage.continuation),
                                                 subscribeButtonText: page.subscribeButtonText,
                                                 isSubscribed: page.isSubscribed)

        cache.setChannelPage(pageWithChannelAvatars, channelId: channelId)
        // Persist static channel info to disk (survives restarts)
        cache.setChannelInfo(page.info, channelId: channelId)
        setPage(pageWithChannelAvatars.videosPage)
        errorLabel.isHidden = !videos.isEmpty
        handleScroll(collectionView)
    }

    @objc private func showAbout() {
        guard let page = currentChannelPage else { return }
        let vc = ChannelAboutViewController(page: page)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc private func subscribeButtonTapped() {
        let wasSubscribed = isSubscribed
        isSubscribed = !wasSubscribed
        subscribeButton.setTitle(isSubscribed ? "Subscribed" : "Subscribe", for: .normal)
        subscribeButton.isEnabled = false
        applyHeaderTheme()

        let completion: (Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.subscribeButton.isEnabled = true
                switch result {
                case .success:
                    print("[Subscribe] \(wasSubscribed ? "unsubscribed" : "subscribed") channelId=\(self.channelId)")
                case .failure(let e):
                    print("[Subscribe] \(wasSubscribed ? "unsubscribe" : "subscribe") failed channelId=\(self.channelId): \(e)")
                    self.isSubscribed = wasSubscribed
                    self.subscribeButton.setTitle(wasSubscribed ? "Subscribed" : "Subscribe", for: .normal)
                    self.applyHeaderTheme()
                }
            }
        }

        if wasSubscribed {
            client.unsubscribeFromChannel(channelId: channelId, completion: completion)
        } else {
            client.subscribeToChannel(channelId: channelId, completion: completion)
        }
    }
}
